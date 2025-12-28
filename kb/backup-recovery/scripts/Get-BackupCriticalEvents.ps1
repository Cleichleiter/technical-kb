# Get-BackupCriticalEvents.ps1
<#
.SYNOPSIS
Collects high-signal backup and VSS-related Windows event log entries.

.DESCRIPTION
Targets common providers/logs associated with backup failures and VSS issues:
- VSS
- VolSnap
- SPP (Software Protection Platform) (sometimes surfaces licensing-related backup tool failures)
- Windows Backup (where applicable)
- Storage / Disk / NTFS
- VSS-related application providers (best-effort)

.PARAMETER DaysBack
How many days back to search.

.PARAMETER MaxEvents
Maximum events returned.

.NOTES
Read-only. Safe for production.
#>

[CmdletBinding()]
param(
    [ValidateRange(1,60)]
    [int]$DaysBack = 14,

    [ValidateRange(1,5000)]
    [int]$MaxEvents = 500
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$start = (Get-Date).AddDays(-$DaysBack)

$providers = @(
    'VSS',
    'VolSnap',
    'Microsoft-Windows-Backup',
    'Microsoft-Windows-Backup-FileRestore',
    'Microsoft-Windows-Backup-Utility',
    'Microsoft-Windows-WindowsBackup',
    'Microsoft-Windows-StorageSpaces-Driver',
    'Microsoft-Windows-Partition',
    'Microsoft-Windows-Ntfs',
    'Microsoft-Windows-Disk',
    'Microsoft-Windows-DriverFrameworks-UserMode'
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
    $issues.Add("Backup/VSS-related Error/Critical events detected: $errCount (last $DaysBack days).") | Out-Null
}

[pscustomobject]@{
    Check        = 'BackupCriticalEvents'
    Timestamp    = Get-Date
    DaysBack     = $DaysBack
    MaxEvents    = $MaxEvents
    Providers    = $providers
    Events       = $eventsOut
    HasIssues    = [bool]($issues.Count -gt 0)
    IssueReasons = $issues
}
