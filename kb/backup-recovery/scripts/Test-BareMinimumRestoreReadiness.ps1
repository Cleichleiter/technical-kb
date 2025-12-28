# Test-BareMinimumRestoreReadiness.ps1
<#
.SYNOPSIS
Assesses minimum restore readiness signals for Windows systems.

.DESCRIPTION
Checks:
- Volume free space (basic restore operations need staging space)
- Presence of VSS writers and stability (calls Test-VSSWriters if available)
- Presence of recovery environment (WinRE) configuration (best-effort)

This does not validate a vendor backup chain; it validates local restore readiness prerequisites.

.PARAMETER RequireAdmin
If set, enforces elevation before running admin-sensitive checks.

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
if ($RequireAdmin) {
    Assert-RunAsAdmin | Out-Null
}

$issues = New-Object System.Collections.Generic.List[string]

# Disk free signals (reuse logic lightly)
$vols = Get-Volume -ErrorAction SilentlyContinue |
    Where-Object { $_.Size -gt 0 } |
    ForEach-Object {
        $freePct = if ($_.Size -gt 0) { [math]::Round(($_.SizeRemaining / $_.Size) * 100, 1) } else { $null }
        [pscustomobject]@{
            DriveLetter = $_.DriveLetter
            SizeBytes   = $_.Size
            FreeBytes   = $_.SizeRemaining
            FreePct     = $freePct
        }
    }

if ($vols) {
    foreach ($v in $vols) {
        if ($v.FreePct -ne $null -and $v.FreePct -lt 5) {
            $issues.Add("Restore readiness risk: extremely low free space on drive $($v.DriveLetter): ($($v.FreePct)% free).") | Out-Null
        }
    }
}

# VSS writers (best-effort)
$vssWriterResult = $null
$testVssPath = Join-Path $PSScriptRoot 'Test-VSSWriters.ps1'
if (Test-Path -LiteralPath $testVssPath) {
    try {
        $vssWriterResult = & $testVssPath -RequireAdmin:$RequireAdmin
        if ($vssWriterResult -and $vssWriterResult.HasIssues -eq $true) {
            $issues.Add("Restore readiness risk: VSS writers show instability or errors.") | Out-Null
        }
    } catch {
        $vssWriterResult = [pscustomobject]@{ Error = $_.Exception.Message }
        $issues.Add("Restore readiness: unable to run Test-VSSWriters.ps1 ($($_.Exception.Message))") | Out-Null
    }
}

# WinRE status (best-effort; some servers do not have WinRE enabled)
$winre = $null
try {
    $reagentc = Get-Command reagentc.exe -ErrorAction Stop
    $out = & $reagentc.Source '/info' 2>&1
    $text = $out | Out-String
    $enabled = $null
    if ($text -match 'Windows RE status:\s*(Enabled|Disabled)') {
        $enabled = $matches[1]
    }

    $winre = [pscustomobject]@{
        ReagentcPath = $reagentc.Source
        Status       = $enabled
        Raw          = $text
    }

    if ($enabled -eq 'Disabled') {
        $issues.Add("WinRE is disabled (may be acceptable on some servers, but impacts local recovery workflows).") | Out-Null
    }
} catch {
    $winre = [pscustomobject]@{ Note = 'reagentc not available or access restricted.' }
}

[pscustomobject]@{
    Check        = 'BareMinimumRestoreReadiness'
    Timestamp    = Get-Date
    Volumes      = $vols
    VSSWriters   = $vssWriterResult
    WinRE        = $winre
    HasIssues    = [bool]($issues.Count -gt 0)
    IssueReasons = $issues
}
