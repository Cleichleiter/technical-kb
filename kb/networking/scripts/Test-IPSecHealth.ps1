# Test-IPSecHealth.ps1
<#
.SYNOPSIS
Collects IPsec/IKE health signals and highlights common failure conditions.

.DESCRIPTION
Collects:
- IKEEXT and PolicyAgent services
- Active IPsec Main Mode / Quick Mode security associations (best-effort)
- IPsec policy store summary (best-effort)
- Windows event log entries related to IKE/IPsec (recent sample)

.PARAMETER DaysBack
How far back to pull IKE/IPsec-related events.

.PARAMETER MaxEvents
Maximum number of events to return.

.PARAMETER RequireAdmin
If set, requires elevation.

.NOTES
Read-only. Safe for production.
Some IPsec cmdlets require elevation or specific Windows editions.
#>

[CmdletBinding()]
param(
    [ValidateRange(1,60)]
    [int]$DaysBack = 7,

    [ValidateRange(1,2000)]
    [int]$MaxEvents = 300,

    [switch]$RequireAdmin
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$shared = Join-Path $PSScriptRoot '_shared'
if (Test-Path -LiteralPath (Join-Path $shared 'Assert-RunAsAdmin.ps1')) {
    . (Join-Path $shared 'Assert-RunAsAdmin.ps1')
}
if ($RequireAdmin) {
    Assert-RunAsAdmin | Out-Null
}

$issues = New-Object System.Collections.Generic.List[string]

# Services
$svcNames = @('IKEEXT','PolicyAgent')
$services = foreach ($n in $svcNames) {
    $s = Get-Service -Name $n -ErrorAction SilentlyContinue
    if ($null -eq $s) {
        $issues.Add("Service not found: $n") | Out-Null
        [pscustomobject]@{ Name=$n; Status=$null; StartType=$null }
    } else {
        if ($s.Status -ne 'Running') {
            $issues.Add("Service not running: $n (Status=$($s.Status))") | Out-Null
        }
        $startType = $null
        try {
            $wmi = Get-CimInstance Win32_Service -Filter "Name='$n'" -ErrorAction Stop
            $startType = $wmi.StartMode
        } catch { }
        [pscustomobject]@{ Name=$n; Status=$s.Status; StartType=$startType }
    }
}

# Security associations (best-effort)
$mmSa = $null
$qmSa = $null
try {
    if (Get-Command Get-NetIPsecMainModeSA -ErrorAction SilentlyContinue) {
        $mmSa = Get-NetIPsecMainModeSA -ErrorAction Stop |
            Select-Object -First 500 |
            Select-Object LocalAddress, RemoteAddress, AuthenticationMethod, EncryptionAlgorithm, IntegrityAlgorithm, KeyModule, LifetimeSeconds
    }
} catch {
    $mmSa = [pscustomobject]@{ Error = $_.Exception.Message }
}

try {
    if (Get-Command Get-NetIPsecQuickModeSA -ErrorAction SilentlyContinue) {
        $qmSa = Get-NetIPsecQuickModeSA -ErrorAction Stop |
            Select-Object -First 500 |
            Select-Object LocalAddress, RemoteAddress, LocalPort, RemotePort, Protocol, EncryptionAlgorithm, IntegrityAlgorithm, PfsGroup, LifetimeSeconds
    }
} catch {
    $qmSa = [pscustomobject]@{ Error = $_.Exception.Message }
}

# If no SAs at all, it might be normal (no tunnels) but call it out as informational
if (($mmSa -is [System.Array] -and $mmSa.Count -eq 0) -and ($qmSa -is [System.Array] -and $qmSa.Count -eq 0)) {
    $issues.Add('No active IPsec security associations detected. If an IPsec tunnel is expected, validate peer reachability and policy configuration.') | Out-Null
}

# Events (best-effort): Security log often requires privileges; use System/Application first
$start = (Get-Date).AddDays(-$DaysBack)

$events = @()
$providers = @('IKEEXT','RasClient','RemoteAccess','Schannel','Microsoft-Windows-Security-Kerberos')
$logs = @('System','Application')

foreach ($log in $logs) {
    foreach ($prov in $providers) {
        try {
            $events += Get-WinEvent -FilterHashtable @{
                LogName      = $log
                ProviderName = $prov
                StartTime    = $start
            } -ErrorAction Stop | Select-Object -First $MaxEvents
        } catch { }
    }
}

$eventOut = $events |
    Sort-Object TimeCreated -Descending |
    Select-Object -First $MaxEvents |
    Select-Object TimeCreated, LogName, ProviderName, Id, LevelDisplayName, Message

# Flag obvious error-level entries
$errCount = @($eventOut | Where-Object { $_.LevelDisplayName -in @('Error','Critical') }).Count
if ($errCount -gt 0) {
    $issues.Add("IKE/IPsec-related Error/Critical events detected: $errCount (last $DaysBack days).") | Out-Null
}

[pscustomobject]@{
    Check        = 'IPSecHealth'
    Timestamp    = Get-Date
    Services     = $services
    MainModeSA   = $mmSa
    QuickModeSA  = $qmSa
    Events       = $eventOut
    HasIssues    = [bool]($issues.Count -gt 0)
    IssueReasons = $issues
}
