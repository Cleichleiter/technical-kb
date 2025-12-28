<#
.SYNOPSIS
Validates IP addressing health on the local host.

.DESCRIPTION
Checks for common misconfigurations and incident triggers:
- APIPA addresses (169.254.0.0/16)
- Missing default gateway on active adapters
- Multiple default gateways (routing ambiguity)
- DNS server missing
- Duplicate IPv4 addresses assigned across adapters (local conflict)
- DHCP vs static state per interface (best-effort)

.NOTES
Read-only. Safe for production.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$issues = New-Object System.Collections.Generic.List[string]

$ipConfigs = Get-NetIPConfiguration -ErrorAction Stop |
    Where-Object { $_.NetAdapter -and $_.NetAdapter.Status -eq 'Up' }

$adapterSummaries = New-Object System.Collections.Generic.List[object]
$allIPv4 = New-Object System.Collections.Generic.List[string]
$defaultGateways = New-Object System.Collections.Generic.List[string]

foreach ($cfg in $ipConfigs) {
    $adapter = $cfg.NetAdapter

    $ipv4 = @($cfg.IPv4Address | ForEach-Object { $_.IPAddress }) | Where-Object { $_ }
    foreach ($i in $ipv4) { $allIPv4.Add($i) | Out-Null }

    $gw = @($cfg.IPv4DefaultGateway | ForEach-Object { $_.NextHop }) | Where-Object { $_ }
    foreach ($g in $gw) { $defaultGateways.Add($g) | Out-Null }

    $dns = @($cfg.DnsServer.ServerAddresses) | Where-Object { $_ }

    # APIPA detection
    $hasApipa = $false
    foreach ($i in $ipv4) {
        if ($i -like '169.254.*') { $hasApipa = $true }
    }
    if ($hasApipa) {
        $issues.Add("APIPA detected on adapter '$($adapter.Name)' (169.254.0.0/16). Likely DHCP failure or disconnected network.") | Out-Null
    }

    # Gateway/DNS presence checks (only if IPv4 exists)
    if ($ipv4.Count -gt 0 -and $gw.Count -eq 0) {
        $issues.Add("No default gateway on active adapter '$($adapter.Name)' with IPv4 assigned. Expect limited/non-routable connectivity.") | Out-Null
    }

    if ($ipv4.Count -gt 0 -and $dns.Count -eq 0) {
        $issues.Add("No DNS server configured on active adapter '$($adapter.Name)'. Name resolution will fail.") | Out-Null
    }

    # DHCP state (best-effort)
    $dhcp = $null
    try {
        $dhcp = Get-NetIPInterface -InterfaceIndex $cfg.InterfaceIndex -AddressFamily IPv4 -ErrorAction Stop
    } catch { }

    $adapterSummaries.Add([pscustomobject]@{
        Name           = $adapter.Name
        InterfaceAlias = $cfg.InterfaceAlias
        InterfaceIndex = $cfg.InterfaceIndex
        Status         = $adapter.Status
        LinkSpeed      = $adapter.LinkSpeed
        DhcpEnabled    = if ($dhcp) { $dhcp.Dhcp } else { $null }
        IPv4Addresses  = $ipv4
        IPv4Gateway    = $gw
        DnsServers     = $dns
    }) | Out-Null
}

# Multiple default gateways (common outage source when VPN adapters are up)
$uniqueGws = $defaultGateways | Select-Object -Unique
if ($uniqueGws.Count -gt 1) {
    $issues.Add("Multiple default gateways detected: $($uniqueGws -join ', '). Review interface/route metrics (VPN/split tunnel scenarios).") | Out-Null
}

# Local duplicate IP detection across adapters (rare but very high-signal)
$dupes = $allIPv4 | Group-Object | Where-Object { $_.Count -gt 1 }
foreach ($d in $dupes) {
    $issues.Add("Duplicate IPv4 address assigned across adapters: $($d.Name). Validate NIC team/bridge/VPN adapters and static assignments.") | Out-Null
}

[pscustomobject]@{
    Check           = 'IPAddressing'
    Timestamp       = Get-Date
    Adapters        = $adapterSummaries
    DefaultGateways = $uniqueGws
    HasIssues       = [bool]($issues.Count -gt 0)
    IssueReasons    = $issues
}
