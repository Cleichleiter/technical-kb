# Test-RoutingTable.ps1
<#
.SYNOPSIS
Validates routing table health and flags common routing issues.

.DESCRIPTION
Checks:
- Default route presence (0.0.0.0/0)
- Multiple default routes (potential asymmetry / VPN metric issues)
- Suspicious persistent routes (optional)
- Route metrics and interface bindings (to identify wrong preferred path)

.PARAMETER IncludeIPv6
Also evaluates IPv6 default routes (::/0).

.PARAMETER IncludePersistentRoutes
Includes persistent routes from the registry (best-effort) to surface “mystery” static routes.

.NOTES
Read-only. Safe for production.
#>

[CmdletBinding()]
param(
    [switch]$IncludeIPv6,
    [switch]$IncludePersistentRoutes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$issues = New-Object System.Collections.Generic.List[string]

# IPv4 routes
$routesV4 = Get-NetRoute -AddressFamily IPv4 -ErrorAction Stop |
    Select-Object DestinationPrefix, NextHop, RouteMetric, InterfaceMetric, ifIndex, PolicyStore

$defaultV4 = $routesV4 | Where-Object { $_.DestinationPrefix -eq '0.0.0.0/0' } |
    Sort-Object RouteMetric, InterfaceMetric

if (@($defaultV4).Count -eq 0) {
    $issues.Add('No IPv4 default route (0.0.0.0/0) found.') | Out-Null
} elseif (@($defaultV4).Count -gt 1) {
    $issues.Add("Multiple IPv4 default routes detected ($(@($defaultV4).Count)). Review metrics and VPN adapters.") | Out-Null
}

# Build ifIndex -> adapter mapping
$ifMap = @{}
Get-NetAdapter -ErrorAction SilentlyContinue | ForEach-Object {
    $ifMap[$_.ifIndex] = $_.Name
}

$defaultV4Detailed = $defaultV4 | ForEach-Object {
    [pscustomobject]@{
        DestinationPrefix = $_.DestinationPrefix
        NextHop           = $_.NextHop
        RouteMetric       = $_.RouteMetric
        InterfaceMetric   = $_.InterfaceMetric
        ifIndex           = $_.ifIndex
        InterfaceName     = $ifMap[$_.ifIndex]
        PolicyStore       = $_.PolicyStore
    }
}

# IPv6 routes (optional)
$defaultV6Detailed = $null
if ($IncludeIPv6) {
    $routesV6 = Get-NetRoute -AddressFamily IPv6 -ErrorAction Stop |
        Select-Object DestinationPrefix, NextHop, RouteMetric, InterfaceMetric, ifIndex, PolicyStore

    $defaultV6 = $routesV6 | Where-Object { $_.DestinationPrefix -eq '::/0' } |
        Sort-Object RouteMetric, InterfaceMetric

    if (@($defaultV6).Count -eq 0) {
        $issues.Add('No IPv6 default route (::/0) found.') | Out-Null
    } elseif (@($defaultV6).Count -gt 1) {
        $issues.Add("Multiple IPv6 default routes detected ($(@($defaultV6).Count)). Review metrics and VPN adapters.") | Out-Null
    }

    $defaultV6Detailed = $defaultV6 | ForEach-Object {
        [pscustomobject]@{
            DestinationPrefix = $_.DestinationPrefix
            NextHop           = $_.NextHop
            RouteMetric       = $_.RouteMetric
            InterfaceMetric   = $_.InterfaceMetric
            ifIndex           = $_.ifIndex
            InterfaceName     = $ifMap[$_.ifIndex]
            PolicyStore       = $_.PolicyStore
        }
    }
}

# Persistent routes (optional, best-effort)
$persistent = $null
if ($IncludePersistentRoutes) {
    try {
        # Persistent routes are stored under:
        # HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\PersistentRoutes
        $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\PersistentRoutes'
        if (Test-Path -LiteralPath $regPath) {
            $vals = (Get-ItemProperty -LiteralPath $regPath).PSObject.Properties |
                Where-Object { $_.Name -notmatch '^PS' } |
                Select-Object Name, Value

            $persistent = foreach ($v in $vals) {
                [pscustomobject]@{
                    Name  = $v.Name
                    Value = $v.Value
                }
            }

            if (@($persistent).Count -gt 0) {
                $issues.Add("Persistent routes detected ($(@($persistent).Count)). Validate they are still required.") | Out-Null
            }
        }
    } catch {
        $persistent = [pscustomobject]@{
            Error = $_.Exception.Message
        }
    }
}

# Identify the most-preferred default route (lowest combined metric)
$preferredDefault = $null
if (@($defaultV4).Count -gt 0) {
    $preferredDefault = $defaultV4Detailed | Select-Object -First 1
}

[pscustomobject]@{
    Check        = 'RoutingTable'
    Timestamp    = Get-Date
    PreferredDefaultRoute = $preferredDefault
    DefaultRoutesIPv4     = $defaultV4Detailed
    DefaultRoutesIPv6     = $defaultV6Detailed
    RoutesIPv4Sample      = $routesV4 | Sort-Object DestinationPrefix, RouteMetric | Select-Object -First 200
    PersistentRoutes       = $persistent
    HasIssues    = [bool]($issues.Count -gt 0)
    IssueReasons = $issues
}
