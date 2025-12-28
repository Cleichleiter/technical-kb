<#
.SYNOPSIS
Consolidates a Network Health run folder into a single JSON report and optional CSV/TXT summaries.

.DESCRIPTION
Reads Summary.json (preferred) and any per-section JSON artifacts in a run folder.
Outputs:
- NetworkHealthReport.json (always)
- NetworkHealthFailures.csv (optional)
- NetworkHealthSummary.txt (optional)

.PARAMETER RunPath
Path to a specific run folder created by Invoke-NetworkHealthCheck.ps1.

.PARAMETER OutputPath
Optional output folder. Defaults to RunPath.

.PARAMETER ExportCsv
If set, exports a failures-only CSV.

.PARAMETER ExportText
If set, exports a human-readable summary TXT.

.NOTES
Read-only. Safe for production.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$RunPath,

    [string]$OutputPath,

    [switch]$ExportCsv,
    [switch]$ExportText
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $RunPath)) {
    throw "RunPath not found: $RunPath"
}

if (-not $OutputPath) {
    $OutputPath = $RunPath
}

if (-not (Test-Path -LiteralPath $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$summaryPath = Join-Path $RunPath 'Summary.json'
$summary = $null
if (Test-Path -LiteralPath $summaryPath) {
    $summary = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

# Load all JSON artifacts in the run folder (excluding the consolidated report if re-run)
$jsonFiles = Get-ChildItem -LiteralPath $RunPath -Filter '*.json' -File -ErrorAction Stop |
    Where-Object { $_.Name -notin @('NetworkHealthReport.json') }

$artifacts = foreach ($f in $jsonFiles) {
    try {
        $obj = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        [pscustomobject]@{
            FileName = $f.Name
            Path     = $f.FullName
            Content  = $obj
        }
    } catch {
        [pscustomobject]@{
            FileName = $f.Name
            Path     = $f.FullName
            Content  = [pscustomobject]@{
                Error = $_.Exception.Message
            }
        }
    }
}

# Attempt to derive a section index if Summary.json is missing
$sectionIndex = $null
if ($summary -and $summary.Sections) {
    $sectionIndex = $summary.Sections
} else {
    $sectionIndex = $artifacts |
        Where-Object { $_.FileName -ne 'Summary.json' } |
        ForEach-Object {
            $name = [System.IO.Path]::GetFileNameWithoutExtension($_.FileName)
            [pscustomobject]@{
                Section   = $name
                Status    = if ($_.Content.Status) { $_.Content.Status } else { 'OK' }
                Timestamp = if ($_.Content.Timestamp) { $_.Content.Timestamp } else { $null }
                Output    = $_.Path
            }
        }
}

# Identify failures for CSV/text exports
$failures = @()
if ($summary -and $summary.Sections) {
    $failures = @($summary.Sections | Where-Object { $_.Status -eq 'FAIL' })
} else {
    # Best-effort: treat artifacts with HasIssues true as warnings
    $failures = @(
        $artifacts |
        Where-Object {
            $_.Content -and $_.Content.Status -eq 'FAIL'
        } |
        ForEach-Object {
            [pscustomobject]@{
                Section = [System.IO.Path]::GetFileNameWithoutExtension($_.FileName)
                Status  = 'FAIL'
                Output  = $_.Path
            }
        }
    )
}

$report = [pscustomobject]@{
    ReportType   = 'NetworkHealthReport'
    GeneratedOn  = Get-Date
    RunPath      = $RunPath
    OutputPath   = $OutputPath
    Summary      = $summary
    SectionIndex = $sectionIndex
    Artifacts    = $artifacts
}

$outJson = Join-Path $OutputPath 'NetworkHealthReport.json'
$report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $outJson -Encoding UTF8

if ($ExportCsv) {
    $csvPath = Join-Path $OutputPath 'NetworkHealthFailures.csv'
    $failures |
        Select-Object Section, Status, Timestamp, Output |
        Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
}

if ($ExportText) {
    $txtPath = Join-Path $OutputPath 'NetworkHealthSummary.txt'

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Network Health Report") | Out-Null
    $lines.Add("GeneratedOn: $(Get-Date)") | Out-Null
    $lines.Add("RunPath: $RunPath") | Out-Null
    $lines.Add("") | Out-Null

    if ($summary) {
        $lines.Add("ComputerName: $($summary.ComputerName)") | Out-Null
        $lines.Add("Include: $($summary.Include)") | Out-Null
        $lines.Add("Sections OK: $($summary.SectionsOk)") | Out-Null
        $lines.Add("Sections FAIL: $($summary.SectionsFail)") | Out-Null
        $lines.Add("Sections SKIP: $($summary.SectionsSkip)") | Out-Null
        $lines.Add("") | Out-Null
    }

    if ($failures.Count -gt 0) {
        $lines.Add("Failures:") | Out-Null
        foreach ($f in $failures) {
            $lines.Add(" - $($f.Section) ($($f.Status))") | Out-Null
        }
    } else {
        $lines.Add("Failures: None detected in Summary.json.") | Out-Null
    }

    $lines | Set-Content -LiteralPath $txtPath -Encoding UTF8
}

[pscustomobject]@{
    OutputJson = $outJson
    OutputCsv  = if ($ExportCsv) { (Join-Path $OutputPath 'NetworkHealthFailures.csv') } else { $null }
    OutputText = if ($ExportText) { (Join-Path $OutputPath 'NetworkHealthSummary.txt') } else { $null }
}
