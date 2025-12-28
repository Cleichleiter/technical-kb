<#
.SYNOPSIS
Checks Windows Time (W32Time) configuration and basic time synchronization health on a Domain Controller.

.DESCRIPTION
Test-TimeSync gathers high-signal time/kerberos-related diagnostics:
- Windows Time service status and start type
- w32tm status/source/peers/configuration
- Recent time service warning/error events (System log)
- Optional stripchart sampling to an external reference (time.windows.com) or custom target
- Optional: checks if this DC is the PDC Emulator (best-effort) because PDC time role matters

WHEN TO USE
- Kerberos/authentication errors (clock skew)
- Logon failures that appear intermittent
- Replication issues with odd error codes or inconsistent behavior
- After moving FSMO roles / verifying PDC emulator is configured to sync externally
- After virtualization host time changes or NTP/firewall modifications

NOTES
- Safe/read-only. Does not change time configuration.
- Stripchart may fail if outbound UDP/123 or DNS is blocked. That is still useful evidence.
#>

[CmdletBinding()]
param(
    # Days back to pull W32Time-related warnings/errors from System log
    [int]$DaysBack = 7,

    # Max time events to return
    [int]$MaxTimeEvents = 200,

    # If set, run stripchart sampling (may require outbound connectivity)
    [switch]$IncludeStripChart,

    # Target for stripchart. Defaults to time.windows.com
    [string]$StripChartTarget = 'time.windows.com',

    # Number of stripchart samples
    [ValidateRange(1,20)]
    [int]$StripChartSamples = 5,

    # Timeout per sample (ms) for stripchart
    [ValidateRange(50,5000)]
    [int]$StripChartPeriodMs = 1000,

    # Best-effort: attempt to identify FSMO PDC emulator holder and note whether local DC is PDC
    [switch]$CheckPdcEmulator
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Cmd {
    param(
        [Parameter(Mandatory)][string]$Command,
        [int]$MaxLines = 2000
    )
    $out = cmd.exe /c $Command 2>&1
    if ($null -eq $out) { return @() }
    $out | Select-Object -First $MaxLines
}

function Test-EventLogExists {
    param([Parameter(Mandatory)][string]$LogName)
    try {
        Get-WinEvent -ListLog $LogName -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Get-TimeEvents {
    param(
        [datetime]$StartTime,
        [int]$MaxEvents
    )

    if (-not (Test-EventLogExists -LogName 'System')) { return @() }

    # Providers commonly associated with Windows Time
    $providers = @(
        'Microsoft-Windows-Time-Service',
        'W32Time'
    )

    try {
        Get-WinEvent -FilterHashtable @{
            LogName   = 'System'
            StartTime = $StartTime
        } -ErrorAction Stop |
        Where-Object {
            $_.LevelDisplayName -in @('Error','Warning') -and
            ($providers -contains $_.ProviderName)
        } |
        Select-Object -First $MaxEvents |
        ForEach-Object {
            [pscustomobject]@{
                TimeCreated = $_.TimeCreated
                Level       = $_.LevelDisplayName
                Id          = $_.Id
                Provider    = $_.ProviderName
                Message     = (($_.Message -replace '\s+',' ').Trim())
            }
        }
    } catch {
        @(
            [pscustomobject]@{
                TimeCreated = $null
                Level       = 'ERROR'
                Id          = $null
                Provider    = 'Get-WinEvent'
                Message     = "Failed to query time events: $($_.Exception.Message)"
            }
        )
    }
}

function Get-ServiceStartMode {
    param([Parameter(Mandatory)][string]$Name)
    try { (Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction Stop).StartMode }
    catch { $null }
}

function Try-GetPdcEmulator {
    # Best-effort: use AD module if present, else return null.
    try {
        if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) { return $null }
        Import-Module ActiveDirectory -ErrorAction Stop | Out-Null
        (Get-ADDomain -ErrorAction Stop).PDCEmulator
    } catch {
        $null
    }
}

$computer = $env:COMPUTERNAME
$now = Get-Date

# Service status
$svc = Get-Service -Name 'W32Time' -ErrorAction SilentlyContinue
$svcStatus = if ($svc) { $svc.Status.ToString() } else { 'NotFound' }
$svcStart  = if ($svc) { (Get-ServiceStartMode -Name 'W32Time') } else { $null }

# w32tm outputs
$status = Invoke-Cmd -Command 'w32tm /query /status' -MaxLines 300
$source = Invoke-Cmd -Command 'w32tm /query /source' -MaxLines 50
$peers  = Invoke-Cmd -Command 'w32tm /query /peers' -MaxLines 300
$config = Invoke-Cmd -Command 'w32tm /query /configuration' -MaxLines 600

# Optional stripchart
$strip = $null
if ($IncludeStripChart) {
    $strip = Invoke-Cmd -Command ("w32tm /stripchart /computer:{0} /samples:{1} /period:{2} /dataonly" -f $StripChartTarget, $StripChartSamples, $StripChartPeriodMs) -MaxLines 300
}

# Events
$start = $now.AddDays(-1 * $DaysBack)
$events = Get-TimeEvents -StartTime $start -MaxEvents $MaxTimeEvents

# PDC emulator (optional)
$pdc = $null
$isLocalPdc = $null
if ($CheckPdcEmulator) {
    $pdc = Try-GetPdcEmulator
    if ($pdc) {
        # Compare by hostname prefix (handles FQDN vs NetBIOS)
        $isLocalPdc = ($pdc -like "$computer*")
    }
}

# Heuristic issues
$issues = New-Object System.Collections.Generic.List[string]

if ($svcStatus -eq 'NotFound') {
    $issues.Add('W32Time service not found.') | Out-Null
} elseif ($svcStatus -ne 'Running') {
    $issues.Add("W32Time service is not running (Status=$svcStatus).") | Out-Null
}

if ($svcStart -eq 'Disabled') {
    $issues.Add('W32Time service start type is Disabled.') | Out-Null
}

# If source contains "Local CMOS Clock" on a DC, that is commonly suspicious (not always wrong, but worth flagging)
if (($source -join ' ') -match '(?i)local cmos clock') {
    $issues.Add("Time source appears to be 'Local CMOS Clock' (verify intended NTP hierarchy, especially for PDC Emulator).") | Out-Null
}

# Time events
$warnErrCount = @($events | Where-Object { $_.Level -in @('Error','Warning') }).Count
if ($warnErrCount -gt 0) {
    $issues.Add("Recent Windows Time warnings/errors found (count=$warnErrCount).") | Out-Null
}

# Stripchart failures are signal too
if ($IncludeStripChart -and ($strip -join "`n") -match '(?i)error|failed|timeout|no such host|could not') {
    $issues.Add("Stripchart indicates errors (connectivity/DNS/NTP may be blocked).") | Out-Null
}

[pscustomobject]@{
    ComputerName = $computer
    Timestamp    = $now

    Service = [pscustomobject]@{
        Name      = 'W32Time'
        Status    = $svcStatus
        StartType = $svcStart
    }

    PdcEmulator = if ($CheckPdcEmulator) {
        [pscustomobject]@{
            Holder     = $pdc
            IsLocalPdc = $isLocalPdc
        }
    } else { $null }

    W32tm = [pscustomobject]@{
        Status        = ($status -join "`n")
        Source        = ($source -join "`n")
        Peers         = ($peers  -join "`n")
        Configuration = ($config -join "`n")
        StripChart    = if ($IncludeStripChart) { ($strip -join "`n") } else { $null }
    }

    Events = [pscustomobject]@{
        DaysBack    = $DaysBack
        EventCount  = @($events).Count
        Items       = $events
    }

    HasTimeIssues = [bool]($issues.Count -gt 0)
    IssueReasons  = $issues
}
