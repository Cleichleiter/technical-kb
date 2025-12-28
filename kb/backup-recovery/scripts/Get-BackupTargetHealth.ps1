# Get-BackupTargetHealth.ps1
<#
.SYNOPSIS
Validates basic health signals for a backup target location (local path or UNC).

.DESCRIPTION
Checks:
- Path exists and is reachable
- Free space (if available)
- Write test (optional; creates and deletes a small temp file)

.PARAMETER TargetPath
Local or UNC path to backup target root (example: \\NAS01\Backups\Server01).

.PARAMETER RequireWriteTest
If set, attempts to create and delete a temp file to validate write permissions.

.NOTES
Write test is optional and uses a tiny temp file; no persistent changes.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TargetPath,

    [switch]$RequireWriteTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$issues = New-Object System.Collections.Generic.List[string]

$exists = Test-Path -LiteralPath $TargetPath
if (-not $exists) {
    $issues.Add("Backup target path not reachable: $TargetPath") | Out-Null
}

$free = $null
$total = $null
$drive = $null

# Best-effort disk space (works for local drive letters and some mapped drives)
try {
    $root = $TargetPath
    if ($TargetPath -match '^[A-Za-z]:\\') {
        $drive = $TargetPath.Substring(0,2)
        $v = Get-Volume -DriveLetter $drive.TrimEnd(':') -ErrorAction Stop
        $free = $v.SizeRemaining
        $total = $v.Size
    }
} catch { }

$writeTest = $null
if ($RequireWriteTest -and $exists) {
    $tmpName = ".backup_write_test_{0}.tmp" -f ([guid]::NewGuid().ToString('N'))
    $tmpPath = Join-Path $TargetPath $tmpName
    try {
        Set-Content -LiteralPath $tmpPath -Value 'backup_write_test' -Encoding UTF8
        Remove-Item -LiteralPath $tmpPath -Force
        $writeTest = $true
    } catch {
        $writeTest = $false
        $issues.Add("Write test failed on target: $TargetPath ($($_.Exception.Message))") | Out-Null
    }
}

[pscustomobject]@{
    Check        = 'BackupTargetHealth'
    Timestamp    = Get-Date
    TargetPath   = $TargetPath
    Exists       = $exists
    TotalBytes   = $total
    FreeBytes    = $free
    WriteTest    = $writeTest
    HasIssues    = [bool]($issues.Count -gt 0)
    IssueReasons = $issues
}
