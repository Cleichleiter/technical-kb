# Test-NameResolutionOrder.ps1
<#
.SYNOPSIS
Surfaces name resolution order and common misconfiguration signals.

.DESCRIPTION
Collects:
- DNS suffix search list and devolution settings
- Per-adapter DNS suffix and register settings
- NRPT rules (if present) (best-effort)
- Hosts file presence (metadata only)

Flags:
- Empty suffix search list on domain-joined systems (best-effort)
- Missing connection-specific suffix on adapters with DNS registration enabled

.NOTES
Read-only. Safe for production.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$issues = New-Object System.Collections.Generic.List[string]

$global = Get-DnsClientGlobalSetting -ErrorAction SilentlyContinue |
    Select-Object SuffixSearchList, UseDevolution, DevolutionLevel

$clients = Get-DnsClient -ErrorAction SilentlyContinue |
    Select-Object InterfaceAlias, InterfaceIndex, ConnectionSpecificSuffix, RegisterThisConnectionsAddress, UseSuffixWhenRegistering

# Domain join heuristic
$cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
$isDomainJoined = $false
$domain = $null
if ($cs) {
    $isDomainJoined = [bool]$cs.PartOfDomain
    $domain = $cs.Domain
}

if ($isDomainJoined -and (-not $global.SuffixSearchList -or $global.SuffixSearchList.Count -eq 0)) {
    $issues.Add('System is domain-joined but DNS suffix search list is empty (may be intentional, but often misconfigured).') | Out-Null
}

foreach ($c in $clients) {
    if ($c.RegisterThisConnectionsAddress -eq $true -and [string]::IsNullOrWhiteSpace($c.ConnectionSpecificSuffix)) {
        $issues.Add("Adapter '$($c.InterfaceAlias)' is set to register in DNS but has no connection-specific suffix.") | Out-Null
    }
}

# NRPT rules (VPN / DirectAccess / Always On VPN environments)
$nrpt = $null
try {
    $nrpt = Get-DnsClientNrptRule -ErrorAction Stop |
        Select-Object Name, Namespace, NameServers, DirectAccessDnsServers, QueryPolicy, Comment
} catch {
    $nrpt = $null
}

$hostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
$hostsInfo = if (Test-Path -LiteralPath $hostsPath) {
    $fi = Get-Item -LiteralPath $hostsPath -ErrorAction SilentlyContinue
    [pscustomobject]@{
        Exists        = $true
        Path          = $hostsPath
        LastWriteTime = $fi.LastWriteTime
        LengthBytes   = $fi.Length
    }
} else {
    [pscustomobject]@{
        Exists        = $false
        Path          = $hostsPath
        LastWriteTime = $null
        LengthBytes   = $null
    }
}

[pscustomobject]@{
    Check        = 'NameResolutionOrder'
    Timestamp    = Get-Date
    DomainJoined = $isDomainJoined
    Domain       = $domain
    GlobalDns    = $global
    PerAdapterDns= $clients
    NrptRules    = $nrpt
    HostsFile    = $hostsInfo
    HasIssues    = [bool]($issues.Count -gt 0)
    IssueReasons = $issues
}
