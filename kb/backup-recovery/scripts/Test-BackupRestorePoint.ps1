# Test-BackupRestorePoint.ps1
<#
.SYNOPSIS
Validates that the system has recoverable snapshot/restore artifacts (best-effort).

.DESCRIPTION
Because backup products vary widely, this script checks common Windows-native indicators:
- Existing shadow copies (VSS)
- System Restore points (where available)

This does not validate vendor backup integrity; it validates the presence of local recovery artifacts.

.PARAMETER RequireAdmin
If set, requires elevation.

.NOTES
Read-only. Safe for production.
#>

[CmdletBinding()]
param(
    [switch]$RequireAdmin
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$shared = Join-Path $PSScriptRoot '_shared'
if (Test-Path -LiteralPath (Join-Path $shared 'Assert-RunAsAdmin.ps1')) {
    . (Join-Path $shared 'Assert-RunAsAdmin.ps1')
}
if ($RequireAdmin -and (Get-Command Assert-RunAsAdmin -ErrorAction SilentlyContinue)) {
    Assert-RunAsAdmin | Out-Null
}

$issues = New-Object System.Collections.Generic.List[string]

# VSS shadow copies
$shadowCopies = @()
try {
    $shadowCopies = Get-CimInstance Win32_ShadowCopy -ErrorAction Stop |
        Select-Object ID, VolumeName, InstallDate, Description, State
} catch {
    $shadowCopies = @()
}

if (@($shadowCopies).Count -eq 0) {
    $issues.Add("No VSS shadow copies detected. If snapshots are expected, validate VSS provider/backup tooling.") | Out-Null
}

# System Restore (often disabled on servers)
$restorePoints = $null
try {
    if (Get-Command Get-ComputerRestorePoint -ErrorAction SilentlyContinue) {
        $restorePoints = Get-ComputerRestorePoint -ErrorAction Stop |
            Select-Object SequenceNumber, Description, RestorePointType, EventType, CreationTime

        if (@($restorePoints).Count -eq 0) {
            $issues.Add("No System Restore points detected (may be disabled or not applicable).") | Out-Null
        }
    } else {
        $restorePoints = [pscustomobject]@{ Note = 'Get-ComputerRestorePoint not available on this system.' }
    }
} catch {
    $restorePoints = [pscustomobject]@{ Error = $_.Exception.Message }
    $issues.Add("Unable to query restore points: $($_.Exception.Message)") | Out-Null
}

[pscustomobject]@{
    Check         = 'BackupRestorePoint'
    Timestamp     = Get-Date
    ShadowCopies  = $shadowCopies
    RestorePoints = $restorePoints
    HasIssues     = [bool]($issues.Count -gt 0)
    IssueReasons  = $issues
}
