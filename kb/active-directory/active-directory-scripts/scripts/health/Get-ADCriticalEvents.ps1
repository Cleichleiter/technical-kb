<#
.SYNOPSIS
Collects recent Active Directory / Domain Controller warning and error events from the most relevant logs.

.DESCRIPTION
Get-ADCriticalEvents pulls Warning/Error events from common DC/AD logs and returns a normalized
object that is easy to filter, export, and include in health-check bundles.

Primary logs (when present):
- System
- Directory Service
- DNS Server
- DFS Replication
- KDC
- Security (optional; requires elevated rights and audit policy)

Use this when you need fast evidence for "why is AD/DC unhealthy?" without immediately running
heavier tooling (dcdiag, repadmin) or when you need supporting telemetry for tickets.

OUTPUT
Returns PSCustomObjects with:
ComputerName, LogName, TimeCreated, Level, Id, Provider, Message, RecordId, MachineName

.EXAMPLE
# Last 3 days of warnings/errors across default logs
.\Get-ADCriticalEvents.ps1 -DaysBack 3

.EXAMPLE
# Last 24 hours, include Security events, export to CSV
.\Get-ADCriticalEvents.ps1 -HoursBack 24 -IncludeSecurity |
  Export-Csv C:\Reports\AD-CriticalEvents.csv -NoTypeInformation

.EXAMPLE
# Only "Directory Service" and "DFS Replication" logs; include Informational; return up to 2000 events
.\Get-ADCriticalEvents.ps1 -Logs 'Directory Service','DFS Replication' -IncludeInformation -MaxEvents 2000

.NOTES
- Safe/read-only. Does not modify system state.
- On some systems, "DNS Server" and "Directory Service" logs exist only on DCs or where the role is installed.
- Security log is optional because it can be large and access-controlled.
#>

[CmdletBinding()]
param(
    # Time window selection: use DaysBack OR HoursBack OR StartTime
    [int]$DaysBack = 3,
    [int]$HoursBack,
    [datetime]$StartTime,

    # Limit number of events pulled per-log (helps keep runs fast on noisy systems)
    [int]$MaxEventsPerLog = 800,

    # Hard cap after merge (helps keep output manageable)
    [int]$MaxEventsTotal = 3000,

    # Logs to query (defaults to common DC/AD logs)
    [string[]]$Logs = @(
        'System',
        'Directory Service',
        'DNS Server',
        'DFS Replication',
        'KDC'
    ),

    # Include Security log (optional)
    [switch]$IncludeSecurity,

    # Include Informational events (default is Warning/Error only)
    [switch]$IncludeInformation,

    # Optional: filter to specific Event IDs
    [int[]]$EventId,

    # Optional: filter to specific providers (sources)
    [string[]]$ProviderName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$computer = $env:COMPUTERNAME

# Determine start time
if ($PSBoundParameters.ContainsKey('StartTime')) {
    $start = $StartTime
}
elseif ($PSBoundParameters.ContainsKey('HoursBack') -and $HoursBack -gt 0) {
    $start = (Get-Date).AddHours(-1 * $HoursBack)
}
else {
    $start = (Get-Date).AddDays(-1 * $DaysBack)
}

# Build final log list
$logList = [System.Collections.Generic.List[string]]::new()
foreach ($l in $Logs) {
    if (-not [string]::IsNullOrWhiteSpace($l)) { $null = $logList.Add($l) }
}
if ($IncludeSecurity) { $null = $logList.Add('Security') }

# Determine levels
# Get-WinEvent filter uses numeric levels: 1=Critical,2=Error,3=Warning,4=Information,5=Verbose
$levels = if ($IncludeInformation) { @(1,2,3,4) } else { @(1,2,3) }

function Test-EventLogExists {
    param([Parameter(Mandatory)][string]$LogName)
    try {
        Get-WinEvent -ListLog $LogName -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

$all = New-Object System.Collections.Generic.List[object]

foreach ($log in $logList) {
    if (-not (Test-EventLogExists -LogName $log)) { continue }

    $filter = @{
        LogName    = $log
        StartTime  = $start
        Level      = $levels
    }

    # Apply optional filters (EventId / ProviderName)
    # Note: FilterHashtable supports Id and ProviderName on most builds.
    if ($EventId)       { $filter.Id = $EventId }
    if ($ProviderName)  { $filter.ProviderName = $ProviderName }

    try {
        $events = Get-WinEvent -FilterHashtable $filter -ErrorAction Stop |
            Select-Object -First $MaxEventsPerLog

        foreach ($e in $events) {
            # Normalize message (reduce whitespace; keep it readable for CSV)
            $msg = if ($e.Message) { ($e.Message -replace '\s+',' ').Trim() } else { '' }

            $obj = [pscustomobject]@{
                ComputerName = $computer
                LogName
