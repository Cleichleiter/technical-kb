<#
.SYNOPSIS
Checks SYSVOL and DFS Replication (DFSR) health on a Domain Controller.

.DESCRIPTION
Test-SYSVOLDFSR validates the most common SYSVOL/DFSR failure modes that lead to GPO issues:
- SYSVOL and NETLOGON shares present
- DFSR service present and running (where applicable)
- DFSR migration state (dfsrmig /getglobalstate)
- Recent DFS Replication log warnings/errors
- Basic folder existence for SYSVOL path
- Optional: backlog checks (environment-dependent; not always available without specifying partners)

WHEN TO USE
- Group Policy not applying / slow policy processing
- SYSVOL mismatch between DCs
- After DC promotion/demotion
- After recovering from replication/network issues
- During domain health baselining

NOTES
- Safe/read-only. Does not change DFSR state.
- Backlog checks are not universally reliable without known sending/receiving partners and access;
  this script focuses on high-signal indicators.
#>

[CmdletBinding()]
param(
    # How many days back to scan DFS Replication event log
    [int]$DaysBack = 3,

    # Max DFSR events to return
    [int]$MaxDfsrEvents = 250,

    # Include basic file listings of SYSVOL\domain and Policies (can be large in some environments)
    [switch]$IncludeSysvolListing,

    # Limit listing depth/entries to keep output manageable
    [int]$MaxListItems = 200
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Cmd {
    param(
        [Parameter(Mandatory)][string]$Command,
        [int]$MaxLines = 1000
    )
    $out = cmd.exe /c $Command 2>&1
    if ($null -eq $out) { return @() }
    $out | Select-Object -First $MaxLines
}

function Test-EventLogExists {
    param([Parameter(Mandatory)][string]$LogName)
    try {
        Get-WinEvent -ListLog $LogName -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Get-DfsrEvents {
    param(
        [datetime]$StartTime,
        [int]$MaxEvents
    )

    if (-not (Test-EventLogExists -LogName 'DFS Replication')) {
        return @(
            [pscustomobject]@{
                TimeCreated = $null
                Level       = 'INFO'
                Id          = $null
                Provider    = 'DFS Replication'
                Message     = "Event log 'DFS Replication' not found (DFSR role/service may not be present)."
            }
        )
    }

    try {
        Get-WinEvent -FilterHashtable @{
            LogName   = 'DFS Replication'
            StartTime = $StartTime
        } -ErrorAction Stop |
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
        @(
            [pscustomobject]@{
                TimeCreated = $null
                Level       = 'ERROR'
                Id          = $null
                Provider    = 'Get-WinEvent'
                Message     = "Failed to query DFS Replication events: $($_.Exception.Message)"
            }
        )
    }
}

function Get-SysvolPath {
    # Default SYSVOL path is %SystemRoot%\SYSVOL\sysvol
    # We derive it from the SYSVOL share if possible; fallback to standard location.
    try {
        $share = Get-SmbShare -Name 'SYSVOL' -ErrorAction Stop
        return $share.Path
    } catch {
        Join-Path $env:SystemRoot 'SYSVOL\sysvol'
    }
}

$computer = $env:COMPUTERNAME
$now = Get-Date
$domain = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).Domain

# Shares
$sysvolShare  = Get-SmbShare -Name 'SYSVOL'   -ErrorAction SilentlyContinue
$netlogonShare= Get-SmbShare -Name 'NETLOGON' -ErrorAction SilentlyContinue

$sysvolSharePresent   = [bool]$sysvolShare
$netlogonSharePresent = [bool]$netlogonShare

# DFSR Service
$dfsrSvc = Get-Service -Name 'DFSR' -ErrorAction SilentlyContinue
$dfsrSvcStatus = if ($dfsrSvc) { $dfsrSvc.Status.ToString() } else { 'NotFound' }

# SYSVOL folder checks
$sysvolRoot = Get-SysvolPath
$sysvolRootExists = Test-Path -LiteralPath $sysvolRoot

$domainSysvolPath = if ($domain) { Join-Path $sysvolRoot $domain } else { $null }
$policiesPath     = if ($domainSysvolPath) { Join-Path $domainSysvolPath 'Policies' } else { $null }
$scriptsPath      = if ($domainSysvolPath) { Join-Path $domainSysvolPath 'Scripts' } else { $null }

$domainSysvolExists = if ($domainSysvolPath) { Test-Path -LiteralPath $domainSysvolPath } else { $false }
$policiesExists     = if ($policiesPath) { Test-Path -LiteralPath $policiesPath } else { $false }
$scriptsExists      = if ($scriptsPath) { Test-Path -LiteralPath $scriptsPath } else { $false }

# DFSR migration global state (helps identify leftover FRS/DFSR transition confusion)
$dfsrMig = Invoke-Cmd -Command 'dfsrmig /getglobalstate' -MaxLines 200

# DFSR events
$start = $now.AddDays(-1 * $DaysBack)
$dfsrEvents = Get-DfsrEvents -StartTime $start -MaxEvents $MaxDfsrEvents

# Optional listings (limited)
$sysvolListing = $null
if ($IncludeSysvolListing -and $policiesExists) {
    try {
        $gpos = Get-ChildItem -LiteralPath $policiesPath -Directory -ErrorAction Stop |
            Select-Object -First $MaxListItems |
            Select-Object Name, FullName, LastWriteTime

        $sysvolListing = [pscustomobject]@{
            PoliciesPath = $policiesPath
            PolicyFolderCountSampled = @($gpos).Count
            PolicyFoldersSample      = $gpos
        }
    } catch {
        $sysvolListing = [pscustomobject]@{
            PoliciesPath = $policiesPath
            Error        = $_.Exception.Message
        }
    }
}

# Heuristic issue flags
$issues = New-Object System.Collections.Generic.List[string]

if (-not $sysvolSharePresent)  { $issues.Add('SYSVOL share is missing.') | Out-Null }
if (-not $netlogonSharePresent){ $issues.Add('NETLOGON share is missing.') | Out-Null }

if ($dfsrSvcStatus -eq 'NotFound') {
    $issues.Add('DFSR service not found (verify SYSVOL replication method / role install).') | Out-Null
} elseif ($dfsrSvcStatus -ne 'Running') {
    $issues.Add("DFSR service is not running (Status=$dfsrSvcStatus).") | Out-Null
}

if (-not $sysvolRootExists)     { $issues.Add("SYSVOL root path missing: $sysvolRoot") | Out-Null }
if ($domain -and -not $domainSysvolExists) { $issues.Add("Domain SYSVOL path missing: $domainSysvolPath") | Out-Null }
if ($domain -and -not $policiesExists)     { $issues.Add("Policies folder missing: $policiesPath") | Out-Null }

$dfsrWarnErrCount = @($dfsrEvents | Where-Object { $_.Level -in @('Error','Warning') }).Count
if ($dfsrWarnErrCount -gt 0) {
    $issues.Add("Recent DFS Replication warnings/errors found (count=$dfsrWarnErrCount).") | Out-Null
}

[pscustomobject]@{
    ComputerName = $computer
    Domain       = $domain
    Timestamp    = $now

    Shares = [pscustomobject]@{
        SysvolPresent   = $sysvolSharePresent
        NetlogonPresent = $netlogonSharePresent
        SysvolPath      = if ($sysvolSharePresent) { $sysvolShare.Path } else { $sysvolRoot }
        NetlogonPath    = if ($netlogonSharePresent) { $netlogonShare.Path } else { $null }
    }

    Paths = [pscustomobject]@{
        SysvolRoot          = $sysvolRoot
        SysvolRootExists    = [bool]$sysvolRootExists
        DomainSysvolPath    = $domainSysvolPath
        DomainSysvolExists  = [bool]$domainSysvolExists
        PoliciesPath        = $policiesPath
        PoliciesExists      = [bool]$policiesExists
        ScriptsPath         = $scriptsPath
        ScriptsExists       = [bool]$scriptsExists
    }

    DFSR = [pscustomobject]@{
        ServiceStatus   = $dfsrSvcStatus
        MigrationState  = ($dfsrMig -join "`n")
        EventWindowDays = $DaysBack
        RecentEvents    = $dfsrEvents
    }

    SysvolListing = $sysvolListing

    HasSysvolOrDfsrIssues = [bool]($issues.Count -gt 0)
    IssueReasons          = $issues
}
