<#
.SYNOPSIS
Runs an Active Directory security assessment by orchestrating available security test scripts.

.DESCRIPTION
- Discovers and runs security test scripts under ..\security\ (relative to this orchestration folder)
- Aggregates findings into a standard object format
- Optionally exports results (JSON/CSV + optional HTML) via Export-ADSecurityFindingsReport.ps1
- Safe: does not overwrite existing output folders unless -Overwrite is used

.NOTES
- Designed to be resilient: missing scripts/modules are logged as warnings and do not stop the run.
- Test scripts should ideally return one or more "finding" objects. If a script returns:
  - $null          => treated as "no findings"
  - a hashtable    => converted into a finding
  - a string       => converted into an informational finding
  - an object/array=> added as-is if it looks like a finding; otherwise wrapped.

.PARAMETER OutputRoot
Root folder where output run folders are created. Defaults to ..\..\reports\ad-security under repo.

.PARAMETER IncludeScriptPatterns
Filename patterns for scripts to execute (relative discovery). Defaults to Test-*.ps1 and Get-*.ps1.

.PARAMETER ExcludeScriptPatterns
Filename patterns to exclude from execution.

.PARAMETER Export
If set, exports findings using Export-ADSecurityFindingsReport.ps1.

.PARAMETER IncludeHtml
If set, include an HTML export in addition to JSON and CSV.

.PARAMETER Overwrite
If set, allows exporting into an existing run folder.

.PARAMETER MaxConcurrent
Reserved for future parallelization. Currently runs sequentially.

.EXAMPLE
.\Invoke-ADSecurityAssessment.ps1

.EXAMPLE
.\Invoke-ADSecurityAssessment.ps1 -IncludeHtml -Export

.EXAMPLE
.\Invoke-ADSecurityAssessment.ps1 -OutputRoot "C:\Reports\ADSecurity" -Export -Overwrite
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputRoot,

    [Parameter(Mandatory = $false)]
    [string[]]$IncludeScriptPatterns = @('Test-*.ps1', 'Get-*.ps1'),

    [Parameter(Mandatory = $false)]
    [string[]]$ExcludeScriptPatterns = @(),

    [Parameter(Mandatory = $false)]
    [switch]$Export,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeHtml,

    [Parameter(Mandatory = $false)]
    [switch]$Overwrite,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1,64)]
    [int]$MaxConcurrent = 1
)

$ErrorActionPreference = 'Stop'

function Ensure-Folder {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function New-Finding {
    param(
        [Parameter(Mandatory)][ValidateSet('Critical','High','Medium','Low','Info','Warning')]
        [string]$Severity,

        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$Category,

        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$Check,

        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [hashtable]$Data,

        [Parameter(Mandatory=$false)]
        [string]$Remediation,

        [Parameter(Mandatory=$false)]
        [string]$Evidence
    )

    [pscustomobject]@{
        Timestamp   = (Get-Date).ToString('s')
        Severity    = $Severity
        Category    = $Category
        Check       = $Check
        Message     = $Message
        Remediation = $Remediation
        Evidence    = $Evidence
        Data        = $Data
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory)][ValidateSet('INFO','WARN','ERROR')]
        [string]$Level,
        [Parameter(Mandatory)][string]$Message
    )
    $ts = (Get-Date).ToString('s')
    Write-Host "[$ts][$Level] $Message"
}

function Try-ImportActiveDirectory {
    try {
        if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
            return $false
        }
        Import-Module ActiveDirectory -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Get-ADContextSafe {
    $ctx = [ordered]@{
        ComputerName = $env:COMPUTERNAME
        UserName     = "$env:USERDOMAIN\$env:USERNAME"
        Domain       = $null
        Forest       = $null
        PDCEmulator  = $null
    }

    if (Try-ImportActiveDirectory) {
        try { $ctx.Domain = (Get-ADDomain).DNSRoot } catch {}
        try { $ctx.Forest = (Get-ADForest).Name } catch {}
        try { $ctx.PDCEmulator = (Get-ADDomain).PDCEmulator } catch {}
    }

    [pscustomobject]$ctx
}

function Normalize-ScriptOutputToFindings {
    param(
        [Parameter(Mandatory)][object]$Output,
        [Parameter(Mandatory)][string]$ScriptName
    )

    $findings = New-Object System.Collections.Generic.List[object]

    if ($null -eq $Output) { return $findings }

    # If the script returns a collection, process each item.
    if ($Output -is [System.Collections.IEnumerable] -and -not ($Output -is [string]) -and -not ($Output -is [hashtable])) {
        foreach ($item in $Output) {
            $findings.AddRange((Normalize-ScriptOutputToFindings -Output $item -ScriptName $ScriptName))
        }
        return $findings
    }

    # Hashtable => wrap
    if ($Output -is [hashtable]) {
        $msg = if ($Output.Message) { [string]$Output.Message } else { "Finding returned from $ScriptName" }
        $sev = if ($Output.Severity) { [string]$Output.Severity } else { 'Info' }
        $cat = if ($Output.Category) { [string]$Output.Category } else { 'General' }
        $chk = if ($Output.Check) { [string]$Output.Check } else { $ScriptName }

        $findings.Add((New-Finding -Severity $sev -Category $cat -Check $chk -Message $msg -Data $Output))
        return $findings
    }

    # String => info
    if ($Output -is [string]) {
        $findings.Add((New-Finding -Severity 'Info' -Category 'General' -Check $ScriptName -Message $Output))
        return $findings
    }

    # Looks like a finding already?
    $props = $Output.PSObject.Properties.Name
    $looksLikeFinding = @('Severity','Category','Check','Message') | ForEach-Object { $props -contains $_ } | Where-Object { $_ } | Measure-Object | Select-Object -ExpandProperty Count
    if ($looksLikeFinding -ge 3) {
        $findings.Add($Output)
        return $findings
    }

    # Unknown object => wrap
    $findings.Add((New-Finding -Severity 'Info' -Category 'General' -Check $ScriptName -Message "Non-standard output captured from $ScriptName" -Data @{ OutputType = $Output.GetType().FullName; Output = $Output }))
    return $findings
}

# -------------------- Paths --------------------
$ScriptsRoot = Split-Path -Parent $PSScriptRoot  # ...\scripts
$SecurityRoot = Join-Path $ScriptsRoot 'security'
$OrchestrationRoot = $PSScriptRoot

if (-not $OutputRoot) {
    $reports = Join-Path (Split-Path -Parent $ScriptsRoot) 'reports'  # ...\active-directory-scripts\reports
    $OutputRoot = Join-Path $reports 'ad-security'
}

Ensure-Folder -Path $OutputRoot

$runStamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
$RunPath  = Join-Path $OutputRoot $runStamp

if (Test-Path -LiteralPath $RunPath) {
    if (-not $Overwrite) {
        throw "Run output path already exists: $RunPath (use -Overwrite to allow)"
    }
}
Ensure-Folder -Path $RunPath

Write-Log -Level INFO -Message "Assessment root: $ScriptsRoot"
Write-Log -Level INFO -Message "Security scripts:  $SecurityRoot"
Write-Log -Level INFO -Message "Run output:       $RunPath"

# -------------------- Context --------------------
$context = Get-ADContextSafe
Write-Log -Level INFO -Message ("Context: Computer={0} Domain={1} Forest={2} PDC={3}" -f $context.ComputerName, ($context.Domain ?? '<unknown>'), ($context.Forest ?? '<unknown>'), ($context.PDCEmulator ?? '<unknown>'))

# Save context
$contextPath = Join-Path $RunPath 'context.json'
$context | ConvertTo-Json -Depth 6 | Out-File -FilePath $contextPath -Encoding utf8

# -------------------- Discover scripts --------------------
if (-not (Test-Path -LiteralPath $SecurityRoot)) {
    Write-Log -Level WARN -Message "Security folder not found: $SecurityRoot"
}

$discovered = New-Object System.Collections.Generic.List[object]

foreach ($pattern in $IncludeScriptPatterns) {
    if (Test-Path -LiteralPath $SecurityRoot) {
        Get-ChildItem -LiteralPath $SecurityRoot -Recurse -File -Filter $pattern -ErrorAction SilentlyContinue |
            ForEach-Object { $discovered.Add($_) | Out-Null }
    }
}

# Exclusions
if ($ExcludeScriptPatterns.Count -gt 0) {
    $discovered = $discovered | Where-Object {
        $file = $_.Name
        $exclude = $false
        foreach ($x in $ExcludeScriptPatterns) {
            if ($file -like $x) { $exclude = $true; break }
        }
        -not $exclude
    }
}

$discovered = $discovered | Sort-Object FullName -Unique

if (-not $discovered -or $discovered.Count -eq 0) {
    Write-Log -Level WARN -Message "No security scripts discovered under: $SecurityRoot"
}

# Save script inventory
$inventoryPath = Join-Path $RunPath 'script-inventory.csv'
$discovered | Select-Object FullName, Name, DirectoryName, Length, LastWriteTime |
    Export-Csv -Path $inventoryPath -NoTypeInformation

Write-Log -Level INFO -Message ("Discovered scripts: {0}" -f $discovered.Count)

# -------------------- Execute --------------------
$allFindings = New-Object System.Collections.Generic.List[object]

foreach ($scriptFile in $discovered) {
    $scriptName = $scriptFile.Name
    $scriptPath = $scriptFile.FullName

    Write-Log -Level INFO -Message "Running: $scriptName"

    try {
        # dot-source so scripts can define functions/return output
        $output = & $scriptPath 2>&1

        # If errors were written to success stream, capture them as warnings
        if ($output -is [System.Management.Automation.ErrorRecord]) {
            $allFindings.Add((New-Finding -Severity 'Warning' -Category 'Execution' -Check $scriptName -Message "Script produced an error record output" -Data @{ Error = [string]$output })) | Out-Null
        }
        else {
            $normalized = Normalize-ScriptOutputToFindings -Output $output -ScriptName $scriptName
            foreach ($f in $normalized) { $allFindings.Add($f) | Out-Null }
        }
    }
    catch {
        $allFindings.Add((New-Finding -Severity 'Warning' -Category 'Execution' -Check $scriptName -Message "Failed to execute script" -Data @{ ScriptPath = $scriptPath; Error = $_.Exception.Message })) | Out-Null
        Write-Log -Level WARN -Message "Failed: $scriptName ($($_.Exception.Message))"
        continue
    }
}

# Basic summary finding if nothing returned
if ($allFindings.Count -eq 0) {
    $allFindings.Add((New-Finding -Severity 'Info' -Category 'Summary' -Check 'Invoke-ADSecurityAssessment' -Message 'No findings were returned by any security scripts.')) | Out-Null
}

# Save raw findings JSON immediately
$rawJsonPath = Join-Path $RunPath 'findings.raw.json'
$allFindings | ConvertTo-Json -Depth 8 | Out-File -FilePath $rawJsonPath -Encoding utf8

# -------------------- Export (optional) --------------------
if ($Export) {
    $exportScript = Join-Path $OrchestrationRoot 'Export-ADSecurityFindingsReport.ps1'
    if (Test-Path -LiteralPath $exportScript) {
        Write-Log -Level INFO -Message "Exporting findings with: $exportScript"
        & $exportScript -InputObject $allFindings -OutputPath $RunPath -BaseName 'ADSecurityFindings' -IncludeHtml:$IncludeHtml -Overwrite:$Overwrite
    }
    else {
        Write-Log -Level WARN -Message "Export script not found: $exportScript"
    }
}

# Return a compact run object
$summary = [pscustomobject]@{
    RunPath     = $RunPath
    Context     = $context
    ScriptCount = $discovered.Count
    FindingCount= $allFindings.Count
    Severity    = ($allFindings | Group-Object Severity | Sort-Object Count -Descending | Select-Object Name, Count)
}

Write-Log -Level INFO -Message ("Complete. Scripts={0} Findings={1}" -f $summary.ScriptCount, $summary.FindingCount)
$summary
