# Export-WindowsHealthReport.ps1
<#
.SYNOPSIS
Exports a consolidated Windows health report from an Invoke-WindowsHealthCheck output folder.

.DESCRIPTION
Reads the JSON section files produced by Invoke-WindowsHealthCheck and produces:
- Consolidated JSON report (single file)
- Optional CSV summaries (problems only)
- Optional flattened "summary.txt" for ticket attachments

This script is intended for post-processing: run it against an existing run folder.

.EXAMPLE
.\Export-WindowsHealthReport.ps1 -RunPath "C:\ProgramData\TechnicalKB\WindowsHealth\SERVER01-20251228-120000" -OutPath "C:\Reports\SERVER01-WindowsHealth.json"

.EXAMPLE
.\Export-WindowsHealthReport.ps1 -RunPath .\out\SERVER01-20251228-120000 -ExportCsv -ExportText

.NOTES
Read-only with respect to the system; writes report artifacts to specified output path.
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
    $defaultName = (Split-Path -Leaf $runFull) + '-Consolidated.json'
    $OutPath = Join-Path $runFull $defaultName
}

# Load all JSON section files except the consolidated outputs we might generate
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
            Section  = $obj
        }) | Out-Null
    } catch {
        $sections.Add([pscustomobject]@{
            FileName = $f.Name
            Section  = [pscustomobject]@{
                Status = 'FAILED_TO_PARSE'
                Error  = $_.Exception.Message
            }
        }) | Out-Null
    }
}

# Attempt to find Summary.json produced by the orchestrator
$summaryFile = $jsonFiles | Where-Object { $_.Name -eq 'Summary.json' } | Select-Object -First 1
$summaryObj = $null
if ($summaryFile) {
    try {
        $summaryObj = (Get-Content -LiteralPath $summaryFile.FullName -Raw -Encoding UTF8) | ConvertFrom-Json -ErrorAction Stop
    } catch { }
}

# Build problems list (best-effort across known section shapes)
$problems = New-Object System.Collections.Generic.List[object]
foreach ($s in $sections) {
    $sec = $s.Section

    # Orchestrator sections typically have { Section, Status, Result } wrappers
    if ($sec.PSObject.Properties.Name -contains 'Result') {
        $r = $sec.Result
        foreach ($prop in @('Problems','IssueReasons','Has*Issues','Has*Concerns')) {
            # handled below in best-effort pattern checks
        }

        if ($r -and ($r.PSObject.Properties.Name -contains 'Problems')) {
            foreach ($p in $r.Problems) {
                $problems.Add([pscustomobject]@{
                    Source = $sec.Section
                    Type   = 'Problems'
                    Item   = $p
                }) | Out-Null
            }
        }

        if ($r -and ($r.PSObject.Properties.Name -contains 'IssueReasons')) {
            foreach ($reason in $r.IssueReasons) {
                $problems.Add([pscustomobject]@{
                    Source = $sec.Section
                    Type   = 'IssueReason'
                    Item   = $reason
                }) | Out-Null
            }
        }
    }
    else {
        # Non-orchestrated section; best-effort
        if ($sec.PSObject.Properties.Name -contains 'Problems') {
            foreach ($p in $sec.Problems) {
                $problems.Add([pscustomobject]@{
                    Source = $s.FileName
                    Type   = 'Problems'
                    Item   = $p
                }) | Out-Null
            }
        }
        if ($sec.PSObject.Properties.Name -contains 'IssueReasons') {
            foreach ($reason in $sec.IssueReasons) {
                $problems.Add([pscustomobject]@{
                    Source = $s.FileName
                    Type   = 'IssueReason'
                    Item   = $reason
                }) | Out-Null
            }
        }
    }
}

# Consolidated report object
$report = [pscustomobject]@{
    RunPath        = $runFull
    GeneratedAt    = Get-Date
    Summary        = $summaryObj
    Sections       = $sections
    Problems       = $problems
}

# Write consolidated JSON
$report | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $OutPath -Encoding UTF8

# Optional CSV
if ($ExportCsv) {
    $csvPath = [System.IO.Path]::ChangeExtension($OutPath, '.csv')
    $problems |
        ForEach-Object {
            [pscustomobject]@{
                Source = $_.Source
                Type   = $_.Type
                Item   = if ($_.Item -is [string]) { $_.Item } else { ($_.Item | ConvertTo-Json -Depth 6 -Compress) }
            }
        } |
        Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
}

# Optional Text summary
if ($ExportText) {
    $txtPath = [System.IO.Path]::ChangeExtension($OutPath, '.txt')

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Windows Health Report") | Out-Null
    $lines.Add("RunPath: $runFull") | Out-Null
    $lines.Add("GeneratedAt: $(Get-Date)") | Out-Null
    $lines.Add("") | Out-Null

    if ($summaryObj) {
        $lines.Add("Summary: OK=$($summaryObj.SectionsOk) FAILED=$($summaryObj.SectionsFail) Output=$($summaryObj.OutputPath)") | Out-Null
        $lines.Add("") | Out-Null
    }

    if ($problems.Count -gt 0) {
        $lines.Add("Problems: $($problems.Count)") | Out-Null
        foreach ($p in ($problems | Select-Object -First 500)) {
            $itemText = if ($p.Item -is [string]) { $p.Item } else { ($p.Item | ConvertTo-Json -Depth 6 -Compress) }
            $lines.Add("- [$($p.Source)] [$($p.Type)] $itemText") | Out-Null
        }
    } else {
        $lines.Add("Problems: None detected by parsable sections.") | Out-Null
    }

    $lines | Set-Content -LiteralPath $txtPath -Encoding UTF8
}

# Return the report object
$report
