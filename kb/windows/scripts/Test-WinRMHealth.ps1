# Test-WMIHealth.ps1
<#
.SYNOPSIS
Performs safe WMI health checks (service state, repository access, and basic query validation).

.DESCRIPTION
Checks:
- Winmgmt (WMI) service status and start type
- Ability to run basic WMI/CIM queries
- Common WMI failure signals (RPC unavailable, invalid class, provider load failures)
- Optional: event log signals related to WMI activity

WHEN TO USE
- RMM failures
- Scripts failing with CIM/WMI errors
- "Invalid class" or "RPC server unavailable" errors
- Troubleshooting inventory/monitoring issues

NOTES
Read-only. Does not reset or salvage the WMI repository.
#>

[CmdletBinding()]
param(
    [switch]$IncludeWmiEvents,
    [int]$DaysBack = 7,
    [int]$MaxEvents = 200
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ServiceStartMode {
    param([Parameter(Mandatory)][string]$Name)
    try { (Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction Stop).StartMode }
    catch { $null }
}

function Test-EventLogExists {
    param([Parameter(Mandatory)][string]$LogName)
    try { Get-WinEvent -ListLog $LogName -ErrorAction Stop | Out-Null; $true }
    catch { $false }
}

$svc = Get-Service -Name 'Winmgmt' -ErrorAction SilentlyContinue
$svcStatus = if ($svc) { $svc.Status.ToString() } else { 'NotFound' }
$svcStart  = if ($svc) { (Get-ServiceStartMode -Name 'Winmgmt') } else { $null }

$tests = New-Object System.Collections.Generic.List[object]
$issues = New-Object System.Collections.Generic.List[string]

function Add-TestResult {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Success,
        [string]$Detail,
        [string]$Error
    )
    $tests.Add([pscustomobject]@{
        TestName = $Name
        Success  = $Success
        Detail   = $Detail
        Error    = $Error
    }) | Out-Null
}

if ($svcStatus -ne 'Running') {
    $issues.Add("Winmgmt service not running (Status=$svcStatus).") | Out-Null
}

# Basic CIM queries
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    Add-TestResult -Name 'CIM:Win32_OperatingSystem' -Success $true -Detail $os.Caption -Error $null
} catch {
    Add-TestResult -Name 'CIM:Win32_OperatingSystem' -Success $false -Detail $null -Error $_.Exception.Message
    $issues.Add('Failed basic CIM query (Win32_OperatingSystem).') | Out-Null
}

try {
    $proc = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
    Add-TestResult -Name 'CIM:Win32_Processor' -Success $true -Detail $proc.Name -Error $null
} catch {
    Add-TestResult -Name 'CIM:Win32_Processor' -Success $false -Detail $null -Error $_.Exception.Message
    $issues.Add('Failed basic CIM query (Win32_Processor).') | Out-Null
}

try {
    $svc2 = Get-CimInstance Win32_Service -Filter "Name='Winmgmt'" -ErrorAction Stop
    Add-TestResult -Name 'CIM:Win32_Service(Winmgmt)' -Success $true -Detail ("StartMode={0}; State={1}" -f $svc2.StartMode, $svc2.State) -Error $null
} catch {
    Add-TestResult -Name 'CIM:Win32_Service(Winmgmt)' -Success $false -Detail $null -Error $_.Exception.Message
    $issues.Add('Failed CIM query of Win32_Service (Winmgmt).') | Out-Null
}

# Optional WMI events
$wmiEvents = $null
if ($IncludeWmiEvents) {
    $start = (Get-Date).AddDays(-1 * $DaysBack)

    # Common logs: System + WMI-Activity Operational (if enabled)
    $items = New-Object System.Collections.Generic.List[object]

    if (Test-EventLogExists -LogName 'System') {
        try {
            $sys = Get-WinEvent -FilterHashtable @{ LogName='System'; StartTime=$start } -ErrorAction Stop |
                Where-Object { $_.LevelDisplayName -in @('Error','Warning') -and $_.ProviderName -match 'WMI|Winmgmt' } |
                Select-Object -First $MaxEvents
            foreach ($e in $sys) {
                $items.Add([pscustomobject]@{
                    LogName     = 'System'
                    TimeCreated = $e.TimeCreated
                    Level       = $e.LevelDisplayName
                    Id          = $e.Id
                    Provider    = $e.ProviderName
                    Message     = (($_.Message -replace '\s+',' ').Trim())
                }) | Out-Null
            }
        } catch {
            $items.Add([pscustomobject]@{
                LogName='System'; TimeCreated=$null; Level='ERROR'; Id=$null; Provider='Get-WinEvent'
                Message="Failed to query System WMI-related events: $($_.Exception.Message)"
            }) | Out-Null
        }
    }

    $wmiAct = 'Microsoft-Windows-WMI-Activity/Operational'
    if (Test-EventLogExists -LogName $wmiAct) {
        try {
            $op = Get-WinEvent -FilterHashtable @{ LogName=$wmiAct; StartTime=$start } -ErrorAction Stop |
                Where-Object { $_.LevelDisplayName -in @('Error','Warning') } |
                Select-Object -First $MaxEvents
            foreach ($e in $op) {
                $items.Add([pscustomobject]@{
                    LogName     = $wmiAct
                    TimeCreated = $e.TimeCreated
                    Level       = $e.LevelDisplayName
                    Id          = $e.Id
                    Provider    = $e.ProviderName
                    Message     = (($_.Message -replace '\s+',' ').Trim())
                }) | Out-Null
            }
        } catch {
            $items.Add([pscustomobject]@{
                LogName=$wmiAct; TimeCreated=$null; Level='ERROR'; Id=$null; Provider='Get-WinEvent'
                Message="Failed to query WMI-Activity events: $($_.Exception.Message)"
            }) | Out-Null
        }
    }

    $wmiEvents = $items | Sort-Object TimeCreated -Descending | Select-Object -First $MaxEvents
    if (@($wmiEvents | Where-Object { $_.Level -in @('Error','Warning') }).Count -gt 0) {
        $issues.Add('WMI-related warnings/errors detected in event logs.') | Out-Null
    }
}

[pscustomobject]@{
    ComputerName = $env:COMPUTERNAME
    Timestamp    = Get-Date

    Service = [pscustomobject]@{
        Name      = 'Winmgmt'
        Status    = $svcStatus
        StartType = $svcStart
    }

    Tests = $tests
    Events = if ($IncludeWmiEvents) {
        [pscustomobject]@{
            DaysBack   = $DaysBack
            EventCount = @($wmiEvents).Count
            Items      = $wmiEvents
        }
    } else { $null }

    HasWmiIssues = [bool]($issues.Count -gt 0)
    IssueReasons = $issues
}
