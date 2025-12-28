<#
.SYNOPSIS
Runs DCDIAG on a Domain Controller and returns a structured result (pass/fail + key findings).

.DESCRIPTION
Test-DCDiag executes dcdiag.exe with a configurable test set and captures:
- Raw output (capped)
- Extracted failure/suspicious lines
- High-level Pass/Fail determination
- Optional per-test selection

This is a core DC health check because it validates multiple AD DS subsystems including:
advertising, services, replication, DNS registration, SYSVOL, topology, KCC, role holders, and more.

WHEN TO USE
- Primary “first deep check” for DC health.
- After patching, promoting/demoting DCs, DNS changes, site changes, or replication incidents.
- As supporting evidence for tickets/escalations.

NOTES
- Safe/read-only (dcdiag reads state).
- Requires dcdiag.exe (present on DCs; also available via RSAT).
- Some tests may be noisy in small/edge environments; tune -Tests accordingly.
#>

[CmdletBinding()]
param(
    # DC to test (default: local)
    [string]$TargetDC = $env:COMPUTERNAME,

    # Commonly useful default tests; adjust to match your environment and tolerance for noise.
    [string[]]$Tests = @(
        'Advertising',
        'Services',
        'Replications',
        'DNS',
        'SysVolCheck',
        'NetLogons',
        'Topology',
        'KccEvent',
        'KnowsOfRoleHolders',
        'VerifyReferences'
    ),

    # If specified, dcdiag will run all tests (ignores -Tests)
    [switch]$AllTests,

    # Include /c (comprehensive) and /e (enterprise) options (can be slower/noisier)
    [switch]$Comprehensive,
    [switch]$Enterprise,

    # Increase verbosity
    [switch]$VerboseOutput,

    # Maximum number of lines to keep from raw output
    [int]$MaxRawLines = 6000,

    # Maximum number of extracted finding lines
    [int]$MaxFindingLines = 400
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-CommandExists {
    param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-Cmd {
    param(
        [Parameter(Mandatory)][string]$Command,
        [int]$MaxLines = 6000
    )
    $out = cmd.exe /c $Command 2>&1
    if ($null -eq $out) { return @() }
    $out | Select-Object -First $MaxLines
}

function Get-FindingLines {
    param(
        [Parameter(Mandatory)][string[]]$Lines,
        [int]$MaxLines = 400
    )

    # Catch common failure patterns without over-matching normal informational output.
    $pattern = '(?i)failed test|fail(ed|ure)?\b|fatal\b|error\b|warning\b|could not|cannot|unreachable|access is denied|rpc server is unavailable|no such domain|name resolution|bad dns|not responding|timeout|not found'
    $Lines | Where-Object { $_ -match $pattern } | Select-Object -First $MaxLines
}

if (-not (Test-CommandExists -Name 'dcdiag.exe')) {
    throw "dcdiag.exe not found. Run on a DC or install RSAT/AD DS tools."
}

# Build dcdiag arguments
$argList = New-Object System.Collections.Generic.List[string]
$argList.Add("/s:$TargetDC") | Out-Null

if ($AllTests) {
    # dcdiag default already runs a broad set; /c tends to be the "comprehensive" run
    # We still allow /c and /e toggles below.
} else {
    foreach ($t in $Tests) {
        if (-not [string]::IsNullOrWhiteSpace($t)) {
            $argList.Add("/test:$t") | Out-Null
        }
    }
}

if ($Comprehensive) { $argList.Add('/c') | Out-Null }
if ($Enterprise)    { $argList.Add('/e') | Out-Null }
if ($VerboseOutput) { $argList.Add('/v') | Out-Null }

# Use a stable output format; /f writes to file but we are capturing stdout for repo usage.
$cmd = "dcdiag {0}" -f ($argList -join ' ')
$raw = Invoke-Cmd -Command $cmd -MaxLines $MaxRawLines

# Extract findings and determine pass/fail
$findings = Get-FindingLines -Lines $raw -MaxLines $MaxFindingLines

# Heuristic: if dcdiag prints "failed test" anywhere, mark as fail.
# This is more reliable than scanning for generic "warning" which can be noisy.
$failedTest = ($raw -match '(?i)failed test')
$passed = -not $failedTest

# Pull a few summary-ish lines if present
$summaryLines = $raw | Where-Object {
    $_ -match '(?i)Starting test:|passed test|failed test|Doing initial|Summary|Diagnosing|test .* completed'
} | Select-Object -First 300

[pscustomobject]@{
    ComputerName  = $env:COMPUTERNAME
    TargetDC      = $TargetDC
    Timestamp     = Get-Date

    Command       = $cmd
    Passed        = [bool]$passed
    FailedTestDetected = [bool]$failedTest

    TestsRequested = if ($AllTests) { 'ALL (default set)' } else { $Tests -join ',' }
    Options        = [pscustomobject]@{
        Comprehensive = [bool]$Comprehensive
        Enterprise    = [bool]$Enterprise
        Verbose       = [bool]$VerboseOutput
    }

    SummaryLines  = ($summaryLines -join "`n")
    FindingLines  = ($findings -join "`n")
    RawOutput     = ($raw -join "`n")
}
