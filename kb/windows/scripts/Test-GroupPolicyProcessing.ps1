# Test-GroupPolicyProcessing.ps1
<#
.SYNOPSIS
Collects high-signal Group Policy processing diagnostics and recent GP-related errors.

.DESCRIPTION
Checks:
- Domain join status (GP is not applicable if not domain joined)
- Last applied policy timestamps and summary (gpresult /r)
- Recent GroupPolicy/Operational warnings/errors (if log exists)
- Optional: common "slow link" / CSE error signals

WHEN TO USE
- GPO not applying
- Slow login / long policy processing
- Missing mapped drives, printers, or security settings tied to GPO
- Post-domain join or post-network changes

NOTES
Read-only. Uses gpresult and event logs.
gpresult may require elevation depending on context.
#>

[CmdletBinding()]
param(
    [int]$DaysBack = 7,
    [int]$MaxEvents = 250
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Cmd {
    param([Parameter(Mandatory)][string]$Command, [int]$MaxLines = 5000)
    $out = cmd.exe /c $Command 2>&1
    if ($null -eq $out) { return @() }
    $out | Select-Object -First $MaxLines
}

function Test-EventLogExists {
    param([Parameter(Mandatory)][string]$LogName)
    try { Get-WinEvent -ListLog $LogName -ErrorAction Stop | Out-Null; $true }
    catch { $false }
}

$cs = Get-CimInstance Win32_ComputerSystem
$isDomainJoined = [bool]$cs.PartOfDomain
$domain = $cs.Domain

$gpResult = @()
$gpResultError = $null
if ($isDomainJoined) {
    try {
        $gpResult = Invoke-Cmd -Command 'gpresult /r' -MaxLines 1200
    } catch {
        $gpResultError = $_.Exception.Message
    }
}

$opLog = 'Microsoft-Windows-GroupPolicy/Operational'
$events = @()
if ($isDomainJoined -and (Test-EventLogExists -LogName $opLog)) {
    $start = (Get-Date).AddDays(-1 * $DaysBack)
    try {
        $events = Get-WinEvent -FilterHashtable @{ LogName=$opLog; StartTime=$start } -ErrorAction Stop |
            Where-Object { $_.LevelDisplayName -in @('Error','Warning') } |
            Select-Object -First $MaxEvents |
            ForEach-Object {
                [pscustomobject]@{
                    TimeCreated = $_.TimeCreated
                    Level       = $_.LevelDisplayName
                    Id          = $_.Id
                    Provider    = $_.ProviderName
                    Message     = (($_.Message -replace '\s+',' ').Trim())
                }
            }
    } catch {
        $events = @(
            [pscustomobject]@{
                TimeCreated = $null
                Level       = 'ERROR'
                Id          = $null
                Provider    = 'Get-WinEvent'
                Message     = "Failed to query GroupPolicy Operational log: $($_.Exception.Message)"
            }
        )
    }
}

# Extract a small summary from gpresult output (best-effort)
$gpSummary = $null
if ($gpResult -and $gpResult.Count -gt 0) {
    $text = $gpResult -join "`n"

    $userSection = $null
    $compSection = $null

    # Heuristic: grab the "COMPUTER SETTINGS" block header area
    $compMatch = [regex]::Match($text, '(?is)COMPUTER SETTINGS.*?(?=USER SETTINGS|\z)')
    if ($compMatch.Success) { $compSection = $compMatch.Value.Trim() }

    $userMatch = [regex]::Match($text, '(?is)USER SETTINGS.*')
    if ($userMatch.Success) { $userSection = $userMatch.Value.Trim() }

    $gpSummary = [pscustomobject]@{
        ComputerSettings = $compSection
        UserSettings     = $userSection
    }
}

$issues = New-Object System.Collections.Generic.List[string]

if (-not $isDomainJoined) {
    $issues.Add('System is not domain-joined; Group Policy processing is not applicable.') | Out-Null
} else {
    if ($gpResultError) { $issues.Add("gpresult failed: $gpResultError") | Out-Null }
    if (@($events | Where-Object { $_.Level -in @('Error','Warning') }).Count -gt 0) {
        $issues.Add('Group Policy warnings/errors detected in GroupPolicy/Operational log.') | Out-Null
    }
}

[pscustomobject]@{
    ComputerName   = $env:COMPUTERNAME
    Timestamp      = Get-Date
    IsDomainJoined = $isDomainJoined
    Domain         = $domain

    GpresultRaw    = if ($isDomainJoined) { ($gpResult -join "`n") } else { $null }
    GpresultSummary= $gpSummary

    GroupPolicyOperational = if ($isDomainJoined) {
        [pscustomobject]@{
            LogName     = $opLog
            DaysBack    = $DaysBack
            EventCount  = @($events).Count
            Events      = $events
            LogPresent  = (Test-EventLogExists -LogName $opLog)
        }
    } else { $null }

    HasGpoIssues = [bool]($issues.Count -gt 0)
    IssueReasons = $issues
}
