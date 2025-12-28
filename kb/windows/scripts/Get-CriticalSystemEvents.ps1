# Get-CriticalSystemEvents.ps1
<#
.SYNOPSIS
Collects recent high-signal Warning/Error events from Windows logs for rapid incident triage.

.DESCRIPTION
Queries commonly useful logs:
- System
- Application
- Setup
- Microsoft-Windows-WindowsUpdateClient/Operational (if present)

Returns normalized objects suitable for JSON/CSV export, plus an extracted "signal lines" summary.

.NOTES
Read-only. Safe for production.
#>

[CmdletBinding()]
param(
    [int]$DaysBack = 3,
    [int]$MaxEventsPerLog = 800,
    [int]$MaxEventsTotal = 3000,

    [string[]]$Logs = @(
        'System',
        'Application',
        'Setup',
        'Microsoft-Windows-WindowsUpdateClient/Operational'
    ),

    [switch]$IncludeInformation,
    [int[]]$EventId,
    [string[]]$ProviderName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$start = (Get-Date).AddDays(-1 * $DaysBack)
$levels = if ($IncludeInformation) { @(1,2,3,4) } else { @(1,2,3) } # 1=Critical,2=Error,3=Warning,4=Information

function Test-EventLogExists {
    param([Parameter(Mandatory)][string]$LogName)
    try { Get-WinEvent -ListLog $LogName -ErrorAction Stop | Out-Null; $true }
    catch { $false }
}

$all = New-Object System.Collections.Generic.List[object]

foreach ($log in $Logs) {
    if (-not (Test-EventLogExists -LogName $log)) { continue }

    $filter = @{
        LogName   = $log
        StartTime = $start
        Level     = $levels
    }
    if ($EventId)      { $filter.Id = $EventId }
    if ($ProviderName) { $filter.ProviderName = $ProviderName }

    try {
        $events = Get-WinEvent -FilterHashtable $filter -ErrorAction Stop |
            Select-Object -First $MaxEventsPerLog

        foreach ($e in $events) {
            $msg = if ($e.Message) { ($e.Message -replace '\s+',' ').Trim() } else { '' }
            $all.Add([pscustomobject]@{
                ComputerName = $env:COMPUTERNAME
                LogName      = $e.LogName
                TimeCreated  = $e.TimeCreated
                Level        = $e.LevelDisplayName
                Id           = $e.Id
                Provider     = $e.ProviderName
                RecordId     = $e.RecordId
                MachineName  = $e.MachineName
                Message      = $msg
            }) | Out-Null
        }
    }
    catch {
        $all.Add([pscustomobject]@{
            ComputerName = $env:COMPUTERNAME
            LogName      = $log
            TimeCreated  = $null
            Level        = 'ERROR'
            Id           = $null
            Provider     = 'Get-WinEvent'
            RecordId     = $null
            MachineName  = $env:COMPUTERNAME
            Message      = "Failed to read log '$log': $($_.Exception.Message)"
        }) | Out-Null
    }
}

$merged = $all | Sort-Object TimeCreated -Descending | Select-Object -First $MaxEventsTotal

# Extract “signals” (lightweight keywords)
$signalPattern = '(?i)\b(fail|failed|failure|fatal|crash|corrupt|disk|ntfs|bugcheck|blue screen|whea|timeout|hung|terminated|access denied|rpc|dns|winrm|wmi|update|0x)\b'
$signals = $merged | Where-Object { $_.Message -match $signalPattern } | Select-Object -First 300

[pscustomobject]@{
    ComputerName = $env:COMPUTERNAME
    Timestamp    = Get-Date
    DaysBack     = $DaysBack
    TotalEvents  = @($merged).Count
    Signals      = $signals
    Events       = $merged
}
