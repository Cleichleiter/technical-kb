# Get-NetworkCriticalEvents.ps1
<#
.SYNOPSIS
Collects high-signal Windows networking-related events for triage and evidence.

.DESCRIPTION
Pulls a targeted set of providers commonly associated with network outages:
- DNS Client Events
- TCPIP
- NDIS
- NetBT
- WLAN AutoConfig (if applicable)
- RasClient (VPN)
- Schannel (TLS-related connectivity)

.PARAMETER DaysBack
How many days back to search.

.PARAMETER MaxEvents
Maximum number of events returned.

.NOTES
Read-only. Safe for production.
#>

[CmdletBinding()]
param(
    [ValidateRange(1,60)]
    [int]$DaysBack = 7,

    [ValidateRange(1,5000)]
    [int]$MaxEvents = 500
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$start = (Get-Date).AddDays(-$DaysBack)

$providers = @(
    'Microsoft-Windows-DNS-Client',
    'Microsoft-Windows-DNS-ClientEvents',
    'Tcpip',
    'Microsoft-Windows-TCPIP',
    'Microsoft-Windows-NDIS',
    'NetBT',
    'Microsoft-Windows-WLAN-AutoConfig',
    'RasClient',
    'RemoteAccess',
    'Schannel'
)

$logs = @('System','Application')

$events = @()
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

$eventsOut = $events |
    Sort-Object TimeCreated -Descending |
    Select-Object -First $MaxEvents |
    Select-Object TimeCreated, LogName, ProviderName, Id, LevelDisplayName, Message

$issues = New-Object System.Collections.Generic.List[string]
$errCount = @($eventsOut | Where-Object { $_.LevelDisplayName -in @('Error','Critical') }).Count
if ($errCount -gt 0) {
    $issues.Add("Networking-related Error/Critical events detected: $errCount (last $DaysBack days).") | Out-Null
}

[pscustomobject]@{
    Check        = 'NetworkCriticalEvents'
    Timestamp    = Get-Date
    DaysBack     = $DaysBack
    MaxEvents    = $MaxEvents
    Providers    = $providers
    Events       = $eventsOut
    HasIssues    = [bool]($issues.Count -gt 0)
    IssueReasons = $issues
}
