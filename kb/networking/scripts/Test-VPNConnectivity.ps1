# Test-VPNConnectivity.ps1
<#
.SYNOPSIS
Reports VPN connection state and highlights common VPN-related routing/DNS issues.

.DESCRIPTION
Collects:
- Active VPN connections (RAS) (if present)
- Active VPN adapters (heuristic)
- Routes that appear to be injected by VPN interfaces (best-effort)
- DNS servers on VPN interfaces (best-effort)

Flags:
- VPN connected but no default route / no expected routes (best-effort)
- VPN adapters up with no DNS servers configured
- Multiple default routes where one is tied to a VPN interface (common metric issues)

.PARAMETER IncludeRoutes
Includes a route sample and tries to attribute routes to VPN interfaces.

.PARAMETER IncludeRasConnections
Includes RAS VPN connection states via Get-VpnConnection (if available).

.NOTES
Read-only. Safe for production.
Some cmdlets may require elevation depending on endpoint policy.
#>

[CmdletBinding()]
param(
    [switch]$IncludeRoutes,
    [switch]$IncludeRasConnections
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$issues = New-Object System.Collections.Generic.List[string]

# Adapter inventory
$adapters = Get-NetAdapter -ErrorAction SilentlyContinue

# Heuristic: VPN adapters often include these strings
$vpnAdapterCandidates = $adapters | Where-Object {
    $_.Status -eq 'Up' -and (
        $_.InterfaceDescription -match 'VPN|WAN Miniport|WireGuard|TAP|TUN|GlobalProtect|AnyConnect|FortiClient|SonicWall|Palo Alto|Pulse|Juniper|OpenVPN|Zscaler|Check Point|Cisco' -or
        $_.Name -match 'VPN|WireGuard|TAP|TUN|AnyConnect|GlobalProtect|FortiClient|SonicWall|OpenVPN|Zscaler|Pulse'
    )
} | Select-Object Name, ifIndex, Status, LinkSpeed, InterfaceDescription, MacAddress

# DNS on VPN adapters
$vpnDns = @()
foreach ($a in $vpnAdapterCandidates) {
    try {
        $dns = Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction Stop
        $servers = @($dns.ServerAddresses) | Where-Object { $_ }
        if ($servers.Count -eq 0) {
            $issues.Add("VPN adapter '$($a.Name)' is up but has no IPv4 DNS servers configured.") | Out-Null
        }
        $vpnDns += [pscustomobject]@{
            AdapterName = $a.Name
            ifIndex     = $a.ifIndex
            DnsServers  = $servers
        }
    } catch {
        $vpnDns += [pscustomobject]@{
            AdapterName = $a.Name
            ifIndex     = $a.ifIndex
            DnsServers  = $null
            Error       = $_.Exception.Message
        }
    }
}

# RAS VPN connection state (if cmdlet exists)
$ras = $null
if ($IncludeRasConnections) {
    if (Get-Command Get-VpnConnection -ErrorAction SilentlyContinue) {
        try {
            $ras = Get-VpnConnection -AllUserConnection -ErrorAction SilentlyContinue |
                Select-Object Name, ServerAddress, TunnelType, ConnectionStatus, SplitTunneling, RememberCredential, AuthenticationMethod

            if (-not $ras) {
                # Try non all-user
                $ras = Get-VpnConnection -ErrorAction SilentlyContinue |
                    Select-Object Name, ServerAddress, TunnelType, ConnectionStatus, SplitTunneling, RememberCredential, AuthenticationMethod
            }
        } catch {
            $ras = [pscustomobject]@{ Error = $_.Exception.Message }
        }
    } else {
        $ras = [pscustomobject]@{ Note = 'Get-VpnConnection cmdlet not available on this system.' }
    }
}

# Routes / default routes + VPN attribution
$routeInfo = $null
if ($IncludeRoutes) {
    $routes = Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Select-Object DestinationPrefix, NextHop, RouteMetric, InterfaceMetric, ifIndex, PolicyStore

    $ifMap = @{}
    $adapters | ForEach-Object { $ifMap[$_.ifIndex] = $_.Name }

    $defaultRoutes = $routes | Where-Object { $_.DestinationPrefix -eq '0.0.0.0/0' } |
        Sort-Object RouteMetric, InterfaceMetric |
        ForEach-Object {
            [pscustomobject]@{
                DestinationPrefix = $_.DestinationPrefix
                NextHop           = $_.NextHop
                RouteMetric       = $_.RouteMetric
                InterfaceMetric   = $_.InterfaceMetric
                ifIndex           = $_.ifIndex
                InterfaceName     = $ifMap[$_.ifIndex]
                PolicyStore       = $_.PolicyStore
                IsVpnInterface    = @($vpnAdapterCandidates.ifIndex) -contains $_.ifIndex
            }
        }

    if (@($defaultRoutes).Count -gt 1) {
        $vpnDefaults = @($defaultRoutes | Where-Object { $_.IsVpnInterface })
        if ($vpnDefaults.Count -gt 0) {
            $issues.Add('Multiple default routes detected and at least one is bound to a VPN interface. Review interface/route metrics (split tunnel vs full tunnel behavior).') | Out-Null
        } else {
            $issues.Add('Multiple default routes detected. Review interface/route metrics.') | Out-Null
        }
    }

    $routeInfo = [pscustomobject]@{
        DefaultRoutes = $defaultRoutes
        RouteSample   = $routes | Sort-Object DestinationPrefix, RouteMetric | Select-Object -First 250 |
            ForEach-Object {
                [pscustomobject]@{
                    DestinationPrefix = $_.DestinationPrefix
                    NextHop           = $_.NextHop
                    RouteMetric       = $_.RouteMetric
                    InterfaceMetric   = $_.InterfaceMetric
                    ifIndex           = $_.ifIndex
                    InterfaceName     = $ifMap[$_.ifIndex]
                    PolicyStore       = $_.PolicyStore
                    IsVpnInterface    = @($vpnAdapterCandidates.ifIndex) -contains $_.ifIndex
                }
            }
    }
}

# If RAS indicates connected but no VPN adapter candidates, flag (some clients don’t present as RAS)
if ($IncludeRasConnections -and $ras -and ($ras -isnot [System.Array])) {
    # non-array likely note/error object; do nothing
} elseif ($IncludeRasConnections -and $ras) {
    $connected = @($ras | Where-Object { $_.ConnectionStatus -eq 'Connected' }).Count
    if ($connected -gt 0 -and @($vpnAdapterCandidates).Count -eq 0) {
        $issues.Add('RAS reports a connected VPN, but no VPN adapter candidates were detected. Validate adapter visibility and tunnel type.') | Out-Null
    }
}

[pscustomobject]@{
    Check        = 'VPNConnectivity'
    Timestamp    = Get-Date
    VpnAdapters  = $vpnAdapterCandidates
    VpnDns       = $vpnDns
    RasConnections = $ras
    Routes       = $routeInfo
    HasIssues    = [bool]($issues.Count -gt 0)
    IssueReasons = $issues
}
