# Test-AzureAVDHealth.ps1
<#
.SYNOPSIS
Collects Azure Virtual Desktop (AVD) inventory and host pool/session host health signals.

.DESCRIPTION
Enumerates:
- Host pools
- Session hosts and their status/allow new session flags (best-effort by module support)

.NOTES
Requires Az.DesktopVirtualization.
Read-only.
#>

[CmdletBinding()]
param(
    [string]$SubscriptionId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$shared = Join-Path $PSScriptRoot '_shared'
. (Join-Path $shared 'Assert-Module.ps1')

Assert-Module -Name @('Az.Accounts','Az.Resources','Az.DesktopVirtualization') | Out-Null

if ($SubscriptionId) {
    Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
}

$ctx = Get-AzContext -ErrorAction Stop

$hostPools = @()
try { $hostPools = Get-AzWvdHostPool -ErrorAction Stop } catch { $hostPools = @() }

$hpResults = New-Object System.Collections.Generic.List[object]

foreach ($hp in $hostPools) {
    $rg = $hp.ResourceGroupName
    $name = $hp.Name

    $sessionHosts = @()
    try { $sessionHosts = Get-AzWvdSessionHost -ResourceGroupName $rg -HostPoolName $name -ErrorAction Stop } catch { $sessionHosts = @() }

    $hpResults.Add([pscustomobject]@{
        HostPoolName      = $name
        ResourceGroup     = $rg
        Location          = $hp.Location
        HostPoolType      = $hp.HostPoolType
        LoadBalancerType  = $hp.LoadBalancerType
        MaxSessionLimit   = $hp.MaxSessionLimit
        SessionHostCount  = @($sessionHosts).Count
        SessionHosts      = $sessionHosts | Select-Object -First 50 |
            Select-Object Name, Status, AllowNewSession, LastHeartBeat, UpdateState
    }) | Out-Null
}

[pscustomobject]@{
    Check        = 'AzureAVDHealth'
    Timestamp    = Get-Date
    Subscription = [pscustomobject]@{ Id = $ctx.Subscription.Id; Name = $ctx.Subscription.Name }
    HostPoolCount= @($hpResults).Count
    HostPools    = $hpResults
}
