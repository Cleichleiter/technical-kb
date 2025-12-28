<#
.SYNOPSIS
Runs a comprehensive AD/DC health check bundle locally and writes results to a timestamped output folder.

.DESCRIPTION
Invoke-DCHealthCheck orchestrates the individual diagnostic scripts in this folder and saves outputs
as both .json (structured) and .txt (human-readable) so you can attach to tickets, compare runs,
or commit sanitized samples to your repo.

What it runs (expects these scripts in the same directory as this file):
- Get-ADCriticalEvents.ps1
- Test-DCPrereqs.ps1
- Test-DCDiag.ps1
- Test-ADReplication.ps1
- Test-DNSHealth.ps1
- Test-SYSVOLDFSR.ps1
- Test-TimeSync.ps1
- Test-DCServices.ps1
- Test-NTDSDatabase.ps1

Output:
$OutputRoot\<ComputerName>-<yyyyMMdd-HHmmss>\
  run.log
  01-Prereqs.json/.txt
  02-CriticalEvents.json/.txt
  03-DCDiag.json/.txt
  04-Replication.json/.txt
  05-DNS.json/.txt
  06-SYSVOL-DFSR.json/.txt
  07-TimeSync.json/.txt
  08-Services.json/.txt
  09-NTDSDatabase.json/.txt
  Summary.json/.txt

WHEN TO USE
- As the primary “one command” DC health check.
- Before/after changes (patching, DNS changes, DC promotion/demotion, site changes).
- During incident response to collect consistent evidence quickly.

NOTES
- Designed to be safe/read-only. It runs diagnostics and reads logs; it does not change configuration.
- Some checks require elevation (Admin) and/or RSAT/AD module depending on environment.
#>

[CmdletBinding()]
param(
    # Root folder for outputs. Defaults to ProgramData for consistency and permissions.
    [string]$OutputRoot = "$env:ProgramData\TechnicalKB\ADHealth",

    # Optional run label to include in output folder name (e.g., "BeforePatch", "AfterDNSFix")
    [string]$RunLabel,

    # Stop on first script failure (default: continue and record failures)
    [switch]$FailFast,

    # Include additional raw outputs where supported (if scripts accept switches later)
    [switch]$IncludeRawOutputs,

    # Days back for event collection
    [int]$EventDaysBack = 3,

    # Optional: If provided, also write a single combined JSON of all sections
    [switch]$WriteCombinedJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Helpers (self-contained; no dependency on Write-HealthLog) ---
function Write-RunLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO',
        [string]$Path
    )
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = "[{0}] [{1}] {2}" -f $ts, $Level, $Message
    Write-Host $line
    if ($Path) { Add-Content -LiteralPath $Path -Value $line -Encoding UTF8 }
}

function Save-Section {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$OutDir
    )

    $jsonPath = Join-Path $OutDir ($Name + '.json')
    $txtPath  = Join-Path $OutDir ($Name + '.txt')

    $Object | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    $Object | Out-String -Width 350     | Set-Content -LiteralPath $txtPath  -Encoding UTF8
}

function Invoke-Section {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [Parameter(Mandatory)][string]$OutDir,
        [Parameter(Mandatory)][string]$LogPath,
        [switch]$FailFast
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-RunLog -Message "Starting: $Name" -Level INFO -Path $LogPath

    try {
        $result = & $ScriptBlock

        $sw.Stop()
        $payload = [pscustomobject]@{
            Section     = $Name
            Status      = 'OK'
            DurationMs  = $sw.ElapsedMilliseconds
            Timestamp   = Get-Date
            Result      = $result
        }

        Save-Section -Name $Name -Object $payload -OutDir $OutDir
        Write-RunLog -Message "Completed: $Name (${($sw.ElapsedMilliseconds)}ms)" -Level INFO -Path $LogPath
        return $payload
    }
    catch {
        $sw.Stop()
        $err = $_

        $payload = [pscustomobject]@{
            Section     = $Name
            Status      = 'FAILED'
            DurationMs  = $sw.ElapsedMilliseconds
            Timestamp   = Get-Date
            Error       = [pscustomobject]@{
                Message = $err.Exception.Message
                Type    = $err.Exception.GetType().FullName
                Script  = $err.InvocationInfo.ScriptName
                Line    = $err.InvocationInfo.ScriptLineNumber
                Position= $err.InvocationInfo.OffsetInLine
                Command = $err.InvocationInfo.MyCommand
            }
        }

        Save-Section -Name $Name -Object $payload -OutDir $OutDir
        Write-RunLog -Message "FAILED: $Name (${($sw.ElapsedMilliseconds)}ms) - $($err.Exception.Message)" -Level ERROR -Path $LogPath

        if ($FailFast) { throw }
        return $payload
    }
}

# --- Determine output directory ---
$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
$labelPart = if ([string]::IsNullOrWhiteSpace($RunLabel)) { '' } else { "-$RunLabel" }
$runDirName = "{0}-{1}{2}" -f $env:COMPUTERNAME, $ts, $labelPart

$runDir = Join-Path $OutputRoot $runDirName
New-Item -ItemType Directory -Path $runDir -Force | Out-Null

$logPath = Join-Path $runDir 'run.log'
Write-RunLog -Message "Invoke-DCHealthCheck starting. Output: $runDir" -Level INFO -Path $logPath
Write-RunLog -Message "ScriptRoot: $PSScriptRoot" -Level INFO -Path $logPath

# --- Validate dependent scripts exist ---
$expected = @(
    'Get-ADCriticalEvents.ps1',
    'Test-DCPrereqs.ps1',
    'Test-DCDiag.ps1',
    'Test-ADReplication.ps1',
    'Test-DNSHealth.ps1',
    'Test-SYSVOLDFSR.ps1',
    'Test-TimeSync.ps1',
    'Test-DCServices.ps1',
    'Test-NTDSDatabase.ps1'
)

$missing = foreach ($f in $expected) {
    $p = Join-Path $PSScriptRoot $f
    if (-not (Test-Path -LiteralPath $p)) { $f }
}
if ($missing) {
    $msg = "Missing required script(s) in '$PSScriptRoot': $($missing -join ', ')"
    Write-RunLog -Message $msg -Level ERROR -Path $logPath
    throw $msg
}

# --- Run sections ---
$sections = New-Object System.Collections.Generic.List[object]

# 01 - prereqs
$sections.Add((Invoke-Section -Name '01-Prereqs' -OutDir $runDir -LogPath $logPath -FailFast:$FailFast -ScriptBlock {
    & (Join-Path $PSScriptRoot 'Test-DCPrereqs.ps1')
})) | Out-Null

# 02 - events
$sections.Add((Invoke-Section -Name '02-CriticalEvents' -OutDir $runDir -LogPath $logPath -FailFast:$FailFast -ScriptBlock {
    & (Join-Path $PSScriptRoot 'Get-ADCriticalEvents.ps1') -DaysBack $EventDaysBack
})) | Out-Null

# 03 - dcdiag
$sections.Add((Invoke-Section -Name '03-DCDiag' -OutDir $runDir -LogPath $logPath -FailFast:$FailFast -ScriptBlock {
    & (Join-Path $PSScriptRoot 'Test-DCDiag.ps1')
})) | Out-Null

# 04 - replication
$sections.Add((Invoke-Section -Name '04-Replication' -OutDir $runDir -LogPath $logPath -FailFast:$FailFast -ScriptBlock {
    & (Join-Path $PSScriptRoot 'Test-ADReplication.ps1')
})) | Out-Null

# 05 - dns
$sections.Add((Invoke-Section -Name '05-DNS' -OutDir $runDir -LogPath $logPath -FailFast:$FailFast -ScriptBlock {
    & (Join-Path $PSScriptRoot 'Test-DNSHealth.ps1')
})) | Out-Null

# 06 - sysvol/dfsr
$sections.Add((Invoke-Section -Name '06-SYSVOL-DFSR' -OutDir $runDir -LogPath $logPath -FailFast:$FailFast -ScriptBlock {
    & (Join-Path $PSScriptRoot 'Test-SYSVOLDFSR.ps1')
})) | Out-Null

# 07 - time
$sections.Add((Invoke-Section -Name '07-TimeSync' -OutDir $runDir -LogPath $logPath -FailFast:$FailFast -ScriptBlock {
    & (Join-Path $PSScriptRoot 'Test-TimeSync.ps1')
})) | Out-Null

# 08 - services
$sections.Add((Invoke-Section -Name '08-Services' -OutDir $runDir -LogPath $logPath -FailFast:$FailFast -ScriptBlock {
    & (Join-Path $PSScriptRoot 'Test-DCServices.ps1')
})) | Out-Null

# 09 - ntds
$sections.Add((Invoke-Section -Name '09-NTDSDatabase' -OutDir $runDir -LogPath $logPath -FailFast:$FailFast -ScriptBlock {
    if ($IncludeRawOutputs) {
        & (Join-Path $PSScriptRoot 'Test-NTDSDatabase.ps1') -IncludeFileDetails
    } else {
        & (Join-Path $PSScriptRoot 'Test-NTDSDatabase.ps1')
    }
})) | Out-Null

# --- Build summary ---
$okCount     = ($sections | Where-Object { $_.Status -eq 'OK' }).Count
$failCount   = ($sections | Where-Object { $_.Status -eq 'FAILED' }).Count
$totalMs     = ($sections | Measure-Object -Property DurationMs -Sum).Sum

$summary = [pscustomobject]@{
    ComputerName = $env:COMPUTERNAME
    Timestamp    = Get-Date
    OutputPath   = $runDir
    LogPath      = $logPath
    SectionsOk   = $okCount
    SectionsFail = $failCount
    TotalMs      = $totalMs
    Sections     = $sections
}

Save-Section -Name 'Summary' -Object $summary -OutDir $runDir

if ($WriteCombinedJson) {
    $combinedPath = Join-Path $runDir 'AllSections.combined.json'
    $summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $combinedPath -Encoding UTF8
}

Write-RunLog -Message "Invoke-DCHealthCheck complete. OK=$okCount FAILED=$failCount Output=$runDir" -Level INFO -Path $logPath

# Final object to pipeline
$summary
