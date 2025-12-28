# Test-BackupStorage.ps1
<#
.SYNOPSIS
Validates local volume free space and storage health signals that commonly impact backups.

.DESCRIPTION
Checks:
- Volume health/operational status (where available)
- Free space percentage (warn/fail thresholds)
- Flags volumes with extremely low free space

.PARAMETER WarnFreePct
Warn if free space percentage is below this value.

.PARAMETER FailFreePct
Fail if free space percentage is below this value.

.NOTES
Read-only. Safe for production.
#>

[CmdletBinding()]
param(
    [ValidateRange(1,99)]
    [int]$WarnFreePct = 15,

    [ValidateRange(1,99)]
    [int]$FailFreePct = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$issues = New-Object System.Collections.Generic.List[string]

$vols = Get-Volume -ErrorAction SilentlyContinue |
    Where-Object { $_.Size -gt 0 } |
    ForEach-Object {
        $freePct = if ($_.Size -gt 0) { [math]::Round(($_.SizeRemaining / $_.Size) * 100, 1) } else { $null }

        if ($freePct -ne $null -and $freePct -lt $FailFreePct) {
            $issues.Add("Low disk free space (FAIL): Drive $($_.DriveLetter): Free=$freePct%") | Out-Null
        } elseif ($freePct -ne $null -and $freePct -lt $WarnFreePct) {
            $issues.Add("Low disk free space (WARN): Drive $($_.DriveLetter): Free=$freePct%") | Out-Null
        }

        [pscustomobject]@{
            DriveLetter       = $_.DriveLetter
            FileSystemLabel   = $_.FileSystemLabel
            FileSystemType    = $_.FileSystemType
            HealthStatus      = $_.HealthStatus
            OperationalStatus = $_.OperationalStatus
            SizeBytes         = $_.Size
            FreeBytes         = $_.SizeRemaining
            FreePct           = $freePct
        }
    }

if (-not $vols) {
    $issues.Add("No volumes returned by Get-Volume (limited visibility or restricted environment).") | Out-Null
}

[pscustomobject]@{
    Check        = 'BackupStorage'
    Timestamp    = Get-Date
    WarnFreePct  = $WarnFreePct
    FailFreePct  = $FailFreePct
    Volumes      = $vols
    HasIssues    = [bool]($issues.Count -gt 0)
    IssueReasons = $issues
}
