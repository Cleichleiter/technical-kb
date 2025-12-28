# Test-VSSWriters.ps1
<#
.SYNOPSIS
Checks VSS writer state and surfaces failed or unstable writers.

.DESCRIPTION
Uses vssadmin list writers to collect:
- Writer name
- State
- Last error

Flags:
- Any writer not in Stable state
- Any writer with non-zero last error

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
if ($RequireAdmin) {
    Assert-RunAsAdmin | Out-Null
}

$issues = New-Object System.Collections.Generic.List[string]

$vssadmin = Get-Command vssadmin.exe -ErrorAction Stop

$out = & $vssadmin.Source 'list' 'writers' 2>&1
$text = $out | Out-String

# Parse blocks
$blocks = ($text -split 'Writer name:').Where({ $_ -and $_.Trim() -ne '' })

$writers = foreach ($b in $blocks) {
    $name = ($b -split "`r?`n")[0].Trim()
    $stateLine = ($b -split "`r?`n") | Where-Object { $_ -match 'State:' } | Select-Object -First 1
    $errLine = ($b -split "`r?`n") | Where-Object { $_ -match 'Last error:' } | Select-Object -First 1

    $state = $null
    $lastError = $null

    if ($stateLine -match 'State:\s*\[(\d+)\]\s*(.+)$') {
        $state = $matches[2].Trim()
    } elseif ($stateLine) {
        $state = $stateLine.Trim()
    }

    if ($errLine -match 'Last error:\s*(.+)$') {
        $lastError = $matches[1].Trim()
    }

    if ($state -and $state -notmatch 'Stable') {
        $issues.Add("VSS writer not stable: $name (State=$state)") | Out-Null
    }
    if ($lastError -and $lastError -notmatch 'No error') {
        $issues.Add("VSS writer last error: $name ($lastError)") | Out-Null
    }

    [pscustomobject]@{
        WriterName = $name
        State      = $state
        LastError  = $lastError
    }
}

[pscustomobject]@{
    Check        = 'VSSWriters'
    Timestamp    = Get-Date
    Writers      = $writers
    HasIssues    = [bool]($issues.Count -gt 0)
    IssueReasons = $issues
    Raw          = $text
}
