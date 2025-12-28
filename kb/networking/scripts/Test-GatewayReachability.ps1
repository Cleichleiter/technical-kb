# Test-GatewayReachability.ps1
<#
.SYNOPSIS
Tests reachability of default gateways for active adapters.

.DESCRIPTION
For each active adapter with an IPv4 default gateway, performs:
- ICMP ping test (Test-Connection) with multiple samples
- ARP cache lookup (best-effort) after ping attempt

.NOTES
Read-only. Safe for production.
#>

[CmdletBinding()]
param(
    [ValidateRange(1,10)]
    [int]$Count = 2,

    [ValidateRange(50,5000)]
    [int]$TimeoutMs = 1000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$issues = New-Object System.Collections.Generic.List[string]
$results = New-Object System.Collections.Generic.List[object]

$configs = Get-NetIPConfiguration -ErrorAction Stop |
    Where-Object { $_.NetAdapter.Status -eq 'Up' }

foreach ($cfg in $configs) {
    $adapter = $cfg.NetAdapter
    $gws = @($cfg.IPv4DefaultGateway | ForEach-Object { $_.NextHop }) | Where-Object { $_ }

    foreach ($gw in $gws) {
        $pingOk = $false
        $latency = $null
        $err = $null

        try {
            $reply = Test-Connection -ComputerName $gw -Count $Count -Quiet -ErrorAction Stop
            $pingOk = [bool]$reply
        } catch {
            $pingOk = $false
            $err = $_.Exception.Message
        }

        # Best-effort latency: one sample detailed
        try {
            $sample = Test-Connection -ComputerName $gw -Count 1 -ErrorAction Stop
            $latency = $sample.ResponseTime
        } catch { }

        # Best-effort ARP/MAC resolution
        $mac = $null
        try {
            $neighbor = Get-NetNeighbor -IPAddress $gw -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($neighbor) { $mac = $neighbor.LinkLayerAddress }
        } catch { }

        if (-not $pingOk) {
            $issues.Add("Default gateway unreachable on adapter '$($adapter.Name)': $gw") | Out-Null
        }

        $results.Add([pscustomobject]@{
            AdapterName   = $adapter.Name
            InterfaceAlias= $cfg.InterfaceAlias
            Gateway       = $gw
            PingSuccess   = $pingOk
            LatencyMs     = $latency
            NeighborMac   = $mac
            Error         = $err
        }) | Out-Null
    }
}

[pscustomobject]@{
    Check        = 'GatewayReachability'
    Timestamp    = Get-Date
    Results      = $results
    HasIssues    = [bool]($issues.Count -gt 0)
    IssueReasons = $issues
}
