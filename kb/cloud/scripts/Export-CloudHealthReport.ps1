# Export-CloudHealthReport.ps1
<#
.SYNOPSIS
Consolidates a CloudHealth run folder into a single JSON report and optional CSV/TXT summaries.

.DESCRIPTION
Reads all *.json files in a run folder (excluding Consolidated.*), and outputs:
- Consolidated JSON report
- Optional CSV of failures
- Optional TXT summary for ticket attachments

.PARAMETER RunPath
Path to a run folder produced by Invoke-CloudHealthCheck.

.PARAMETER OutPath
Optional output path for consolidated JSON. Defaults to <RunPath>\Consolidated.json.

.PARAMETER ExportCsv
Also writes <OutPath>.csv (failures only).

.PARAMETER ExportText
Also writes <OutPath>.txt (summary).

#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$RunPath,
    [string]$OutPath,
    [switch]$ExportCsv,
    [switch]$ExportText
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $RunPath)) {
    throw "RunPath not found: $RunPath"
}

$runFull = (Resolve-Path -LiteralPath $RunPath).Path

if (-not $OutPath) {
    $OutPath = Join-Path $runFull 'Consolidated.json'
}

$jsonFiles = Get-ChildItem -LiteralPath $runFull -Filter '*.json' -File |
    Where-Object { $_.Name -notmatch '(?i)Consolidated' } |
    Sort-Object Name

$sections = New-Object System.Collections.Generic.List[object]
foreach ($f in $jsonFiles) {
    try {
        $raw = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
        $sections.Add([pscustomobject]@{
            FileName = $f.Name
            Data     = $obj
        }) | Out-Null
    } catch {
        $sections.Add([pscustomobject]@{
            FileName = $f.Name
            Data     = [pscustomobject]@{
                Status = 'FAILED_TO_PARSE'
                Error  = $_.Exception.Message
            }
        }) | Out-Null
    }
}

# Failure extraction (best-effort)
$fails = $sections | Where-Object {
    ($_.Data.PSObject.Properties.Name -contains 'Status' -and $_.Data.Status -eq 'FAIL') -or
    ($_.FileName -match '^Summary\.json$' -and $_.Data.SectionsFail -gt 0)
}

$report = [pscustomobject]@{
    RunPath     = $runFull
    GeneratedAt = Get-Date
    Sections    = $sections
    Failures    = $fails
}

$report | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $OutPath -Encoding UTF8

if ($ExportCsv) {
    $csvPath = [System.IO.Path]::ChangeExtension($OutPath, '.csv')
    $fails |
        ForEach-Object {
            [pscustomobject]@{
                FileName = $_.FileName
                Error    = if ($_.Data.PSObject.Properties.Name -contains 'Error') { $_.Data.Error } else { $null }
            }
        } |
        Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
}

if ($ExportText) {
    $txtPath = [System.IO.Path]::ChangeExtension($OutPath, '.txt')
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Cloud Health Consolidated Report") | Out-Null
    $lines.Add("RunPath: $runFull") | Out-Null
    $lines.Add("GeneratedAt: $(Get-Date)") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("JSON Files: $($jsonFiles.Count)") | Out-Null
    $lines.Add("Failures Detected: $(@($fails).Count)") | Out-Null
    $lines.Add("") | Out-Null

    foreach ($f in $fails) {
        $err = if ($f.Data.PSObject.Properties.Name -contains 'Error') { $f.Data.Error } else { '' }
        $lines.Add("- $($f.FileName) $err") | Out-Null
    }

    $lines | Set-Content -LiteralPath $txtPath -Encoding UTF8
}

$report
