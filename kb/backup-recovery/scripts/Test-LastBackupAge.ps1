# Test-LastBackupAge.ps1
<#
.SYNOPSIS
Estimates "time since last backup" using Windows-native signals (best-effort).

.DESCRIPTION
Because backup products vary, this script checks:
- Most recent VSS shadow copy creation time
- Most recent Windows Backup event (if present)

Flags if the most recent signal exceeds MaxAgeHours.

.PARAMETER MaxAgeHours
Fail if last backup indicator is older than this threshold.

.PARAMETER DaysBack
How far back to search for Windows Backup events.

.NOTES
Read-only. Safe for production.
This is a heuristic. Vendor platforms should provide authoritative backup timestamps.
#>

[CmdletBinding()]
param(
    [ValidateRange(1,720)]
    [int]$MaxAgeHours = 24,

    [ValidateRange(1,60)]
    [int]$DaysBack = 14
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$issues = New-Object System.Collections.Generic.List[string]
$now = Get-Date

# Latest shadow copy
$latestShadow = $null
try {
    $sh = Get-CimInstance Win32_ShadowCopy -ErrorAction Stop |
        Select-Object InstallDate, VolumeName |
        Sort-Object InstallDate -Descending |
        Select-Object -First 1

    if ($sh -and $sh.InstallDate) {
        $latestShadow = [datetime]$sh.InstallDate
    }
} catch { }

# Latest Windows Backup event (best-effort)
$latestWbEvent = $null
try {
    $start = $now.AddDays(-$DaysBack)
    $ev = Get-WinEvent -FilterHashtable @{
        LogName      = 'Application'
        ProviderName = 'Microsoft-Windows-Backup'
        StartTime    = $start
    } -ErrorAction Stop |
    Sort-Object TimeCreated -Descending |
    Select-Object -First 1

    if ($ev) { $latestWbEvent = $ev.TimeCreated }
} catch { }

# Pick most recent signal
$signals = @()
if ($latestShadow)  { $signals += [pscustomobject]@{ Source='VSSShadowCopy';       Time=$latestShadow } }
if ($latestWbEvent) { $signals += [pscustomobject]@{ Source='WindowsBackupEvent';  Time=$latestWbEvent } }

$best = $signals | Sort-Object Time -Descending | Select-Object -First 1

$ageHours = $null
if ($best) {
    $ageHours = [math]::Round((($now - $best.Time).TotalHours), 2)
    if ($ageHours -gt $MaxAgeHours) {
        $issues.Add("Last backup indicator is older than threshold: $ageHours hours (MaxAgeHours=$MaxAgeHours).") | Out-Null
    }
} else {
    $issues.Add("No backup timestamp indicators found (no shadow copies or Windows Backup events in scope).") | Out-Null
}

[pscustomobject]@{
    Check        = 'LastBackupAge'
    Timestamp    = $now
    MaxAgeHours  = $MaxAgeHours
    DaysBack     = $DaysBack
    BestSignal   = $best
    AllSignals   = $signals
    AgeHours     = $ageHours
    HasIssues    = [bool]($issues.Count -gt 0)
    IssueReasons = $issues
}
