<#
.SYNOPSIS
Exports AD security findings to JSON and CSV (and optional HTML).

.DESCRIPTION
- Accepts findings via -InputObject (recommended) or -InputPath (JSON)
- Writes:
  - <BaseName>.json
  - <BaseName>.csv
  - <BaseName>.summary.html (optional)
- Does not overwrite existing files unless -Overwrite is used

.PARAMETER InputObject
Findings objects to export.

.PARAMETER InputPath
Path to an existing findings JSON file to export.

.PARAMETER OutputPath
Folder to write exports into.

.PARAMETER BaseName
Base filename (without extension) for export artifacts.

.PARAMETER IncludeHtml
If set, generates an HTML summary report.

.PARAMETER Overwrite
If set, overwrites existing output files.

.EXAMPLE
.\Export-ADSecurityFindingsReport.ps1 -InputPath .\findings.raw.json -OutputPath .\ -BaseName ADSecurityFindings

.EXAMPLE
.\Export-ADSecurityFindingsReport.ps1 -InputObject $findings -OutputPath C:\Reports\Run1 -BaseName ADSecurityFindings -IncludeHtml
#>

[CmdletBinding(DefaultParameterSetName = 'Object')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Object')]
    [ValidateNotNull()]
    [object[]]$InputObject,

    [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
    [ValidateNotNullOrEmpty()]
    [string]$InputPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$BaseName = 'ADSecurityFindings',

    [Parameter(Mandatory = $false)]
    [switch]$IncludeHtml,

    [Parameter(Mandatory = $false)]
    [switch]$Overwrite
)

$ErrorActionPreference = 'Stop'

function Ensure-Folder {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Assert-CanWriteFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][switch]$Overwrite)

    if (Test-Path -LiteralPath $Path) {
        if (-not $Overwrite) {
            throw "Output file already exists: $Path (use -Overwrite to allow)"
        }
    }
}

Ensure-Folder -Path $OutputPath

# Load input if needed
$findings =
    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        if (-not (Test-Path -LiteralPath $InputPath)) {
            throw "InputPath not found: $InputPath"
        }
        $raw = Get-Content -LiteralPath $InputPath -Raw -Encoding utf8
        $raw | ConvertFrom-Json
    }
    else {
        $InputObject
    }

# Normalize to an array
if ($null -eq $findings) { $findings = @() }
if ($findings -isnot [System.Collections.IEnumerable] -or $findings -is [string]) { $findings = @($findings) }

# Prepare export targets
$jsonPath = Join-Path $OutputPath ("{0}.json" -f $BaseName)
$csvPath  = Join-Path $OutputPath ("{0}.csv"  -f $BaseName)
$htmlPath = Join-Path $OutputPath ("{0}.summary.html" -f $BaseName)

Assert-CanWriteFile -Path $jsonPath -Overwrite:$Overwrite
Assert-CanWriteFile -Path $csvPath  -Overwrite:$Overwrite
if ($IncludeHtml) { Assert-CanWriteFile -Path $htmlPath -Overwrite:$Overwrite }

# Export JSON (preserve Data field)
$findings | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding utf8

# Flatten for CSV
$flattened = foreach ($f in $findings) {
    # Data can be complex; serialize it into compact JSON for CSV readability
    $dataJson = $null
    try {
        if ($null -ne $f.Data) { $dataJson = ($f.Data | ConvertTo-Json -Depth 6 -Compress) }
    } catch { $dataJson = '[unserializable]' }

    [pscustomobject]@{
        Timestamp   = $f.Timestamp
        Severity    = $f.Severity
        Category    = $f.Category
        Check       = $f.Check
        Message     = $f.Message
        Remediation = $f.Remediation
        Evidence    = $f.Evidence
        Data        = $dataJson
    }
}

$flattened | Export-Csv -Path $csvPath -NoTypeInformation -Encoding utf8

# Optional HTML summary
if ($IncludeHtml) {
    $severityCounts = $flattened | Group-Object Severity | Sort-Object Count -Descending
    $categoryCounts = $flattened | Group-Object Category | Sort-Object Count -Descending

    $top10 = $flattened |
        Sort-Object @{
            Expression = {
                switch ($_.Severity) {
                    'Critical' { 0 }
                    'High'     { 1 }
                    'Medium'   { 2 }
                    'Low'      { 3 }
                    'Warning'  { 4 }
                    default    { 5 }
                }
            }
        }, Timestamp |
        Select-Object -First 10

    $header = @"
<h1>Active Directory Security Findings Summary</h1>
<p><b>Generated:</b> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
<p><b>Total findings:</b> $($flattened.Count)</p>
<hr/>
"@

    $sevHtml = ($severityCounts | Select-Object Name, Count | ConvertTo-Html -Fragment -PreContent "<h2>Findings by Severity</h2>")
    $catHtml = ($categoryCounts | Select-Object Name, Count | ConvertTo-Html -Fragment -PreContent "<h2>Findings by Category</h2>")
    $topHtml = ($top10 | Select-Object Timestamp, Severity, Category, Check, Message | ConvertTo-Html -Fragment -PreContent "<h2>Top Findings (first 10)</h2>")

    $full = $header + $sevHtml + $catHtml + $topHtml + "<hr/><p>See JSON/CSV exports for full details.</p>"
    $full | Out-File -FilePath $htmlPath -Encoding utf8
}

Write-Host "Export complete:"
Write-Host " - JSON: $jsonPath"
Write-Host " - CSV : $csvPath"
if ($IncludeHtml) { Write-Host " - HTML: $htmlPath" }

[pscustomobject]@{
    OutputPath    = $OutputPath
    JsonPath      = $jsonPath
    CsvPath       = $csvPath
    Ht
