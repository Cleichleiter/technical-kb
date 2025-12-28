<#
.SYNOPSIS
Performs an Active Directory replication health check from a Domain Controller.

.DESCRIPTION
Test-ADReplication runs a focused set of replication diagnostics using repadmin and related checks
to identify common replication failures and likely root causes (DNS, RPC, secure channel, etc.).

It collects:
- repadmin /replsummary (overall replication health)
- repadmin /showrepl (partner status and last error per naming context)
- repadmin /queue (replication queue depth)
- repadmin /failcache (recent failures cache)
- Basic DC locator / domain trust signal (nltest /dsgetdc, /sc_verify)

It returns a structured object with raw outputs plus extracted "signals" to surface issues quickly.

WHEN TO USE
- Suspected replication issues (stale GPOs, SYSVOL mismatch, password not syncing, DC promotion)
- Prior to troubleshooting SYSVOL/DFSR or DNS symptoms
- After network/site changes, VPN changes, or firewall rule updates impacting RPC/LDAP

NOTES
- Safe/read-only.
- Requires repadmin.exe (available on DCs / RSAT tools).
- Some outputs can be long; use -MaxRawLines to cap captured raw output.
#>

[CmdletBinding()]
param(
    # Computer name of the local DC (default) or a specific DC to query for /showrepl.
    [string]$TargetDC = $env:COMPUTERNAME,

    # Maximum number of lines to retain from each raw command output
    [int]$MaxRawLines = 4000,

    # Maximum number of extracted "signal" lines to include
    [int]$MaxSignalLines = 300,

    # Include additional optional repadmin commands
    [switch]$IncludeDetailed,
    [switch]$IncludeLingeringChecks
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Cmd {
    param(
        [Parameter(Mandatory)][string]$Command,
        [int]$MaxLines = 4000
    )
    $out = cmd.exe /c $Command 2>&1
    if ($null -eq $out) { return @() }
    $out | Select-Object -First $MaxLines
}

function Get-SignalLines {
    param(
        [Parameter(Mandatory)][string[]]$Lines,
        [int]$MaxLines = 300
    )

    # Common AD replication error codes / keywords:
    # 1722 RPC server unavailable
    # 1753 no endpoints available
    # 8452 naming context in the process of being removed
    # 8606 insufficient attributes
    # 1256 remote system not available
    # 1908 cannot find domain controller
    $pattern = '(?i)\b(fail|fails|failed|failure|error|fatal|unreachable|denied|refused|timeout)\b|1722|1753|8452|8453|8606|1256|1908|access is denied|rpc server is unavailable|no more endpoints|target principal name|the kerberos|dns lookup failure'
    $Lines | Where-Object { $_ -match $pattern } | Select-Object -First $MaxLines
}

function Test-CommandExists {
    param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

# Pre-flight
$missing = @()
foreach ($c in @('repadmin.exe','nltest.exe')) {
    if (-not (Test-CommandExists -Name $c)) { $missing += $c }
}
if ($missing.Count -gt 0) {
    throw "Missing required command(s): $($missing -join ', '). Ensure you are running on a DC or have RSAT installed."
}

# Run commands
$replSummary = Invoke-Cmd -Command 'repadmin /replsummary' -MaxLines $MaxRawLines
$showRepl    = Invoke-Cmd -Command ("repadmin /showrepl {0} /all /verbose" -f $TargetDC) -MaxLines $MaxRawLines
$queue       = Invoke-Cmd -Command 'repadmin /queue' -MaxLines $MaxRawLines
$failCache   = Invoke-Cmd -Command 'repadmin /failcache' -MaxLines $MaxRawLines

# Optional deeper checks
$bridgeheads = @()
$kcc         = @()
$replMeta    = @()
$lingering   = @()

if ($IncludeDetailed) {
    $bridgeheads = Invoke-Cmd -Command ("repadmin /bridgeheads {0}" -f $TargetDC) -MaxLines $MaxRawLines
    $kcc         = Invoke-Cmd -Command ("repadmin /kcc {0}" -f $TargetDC) -MaxLines $MaxRawLines
    # /showutdvec can be very large; keep it optional and capped
    $replMeta    = Invoke-Cmd -Command ("repadmin /showutdvec {0} * /latency" -f $TargetDC) -MaxLines $MaxRawLines
}

if ($IncludeLingeringChecks) {
    # Best-effort: lingering object checks require a source DC and naming context; this command can vary.
    # We'll capture a help/usage hint rather than guess potentially disruptive parameters.
    $lingering = @(
        "Lingering object checks are environment-specific.",
        "Recommended manual run (example): repadmin /removelingeringobjects <DestDC> <SourceDC> <NC> /ADVISORY_MODE",
        "Capture results here after you tailor the command to your environment."
    )
}

# DC locator and secure channel checks (best-effort)
$domain = (Get-CimInstance Win32_ComputerSystem).Domain
$dsgetdc = Invoke-Cmd -Command ("nltest /dsgetdc:{0}" -f $domain) -MaxLines 500
$scverify = Invoke-Cmd -Command ("nltest /sc_verify:{0}" -f $domain) -MaxLines 500

# Extract signals
$signals = New-Object System.Collections.Generic.List[string]
$signals.AddRange((Get-SignalLines -Lines $replSummary -MaxLines $MaxSignalLines)) | Out-Null
$signals.AddRange((Get-SignalLines -Lines $showRepl    -MaxLines $MaxSignalLines)) | Out-Null
$signals.AddRange((Get-SignalLines -Lines $queue       -MaxLines $MaxSignalLines)) | Out-Null
$signals.AddRange((Get-SignalLines -Lines $failCache   -MaxLines $MaxSignalLines)) | Out-Null

# Quick heuristic flags
$hasErrors =
    ($signals.Count -gt 0) -or
    ($replSummary -match '(?i)\bfails?\b') -or
    ($showRepl -match '(?i)Last error') -or
    ($showRepl -match '(?i)result\s+\d+') # repadmin sometimes prints "result 1722" etc.

# Build output object
[pscustomobject]@{
    ComputerName      = $env:COMPUTERNAME
    TargetDC          = $TargetDC
    Domain            = $domain
    Timestamp         = Get-Date

    HasReplicationIssues = [bool]$hasErrors
    SignalLines          = $signals | Select-Object -First $MaxSignalLines

    # DC locator / secure channel quick outputs (helpful for DNS/trust hints)
    DcLocatorRaw      = $dsgetdc -join "`n"
    SecureChannelRaw  = $scverify -join "`n"

    # Raw command outputs (capped)
    ReplSummaryRaw    = $replSummary -join "`n"
    ShowReplRaw       = $showRepl -join "`n"
    QueueRaw          = $queue -join "`n"
    FailCacheRaw      = $failCache -join "`n"

    # Optional sections
    BridgeheadsRaw    = if ($IncludeDetailed) { $bridgeheads -join "`n" } else { $null }
    KccRaw            = if ($IncludeDetailed) { $kcc -join "`n" } else { $null }
    UtdVecLatencyRaw  = if ($IncludeDetailed) { $replMeta -join "`n" } else { $null }

    LingeringNotes    = if ($IncludeLingeringChecks) { $lingering -join "`n" } else { $null }
}
