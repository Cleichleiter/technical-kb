# Get-AzureSubscriptionInventory.ps1
<#
.SYNOPSIS
Collects a lightweight Azure inventory snapshot for the current subscription.

.DESCRIPTION
Returns high-signal counts and selected resource metadata:
- Resource group count
- VM count and status summary
- VNet count
- Public IP count

.NOTES
Requires Az.Accounts, Az.Resources, Az.Compute, Az.Network.
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

Assert-Module -Name @('Az.Accounts','Az.Resources','Az.Compute','Az.Network') | Out-Null

if ($SubscriptionId) {
    Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
}

$ctx = Get-AzContext -ErrorAction Stop

$rgs = Get-AzResourceGroup -ErrorAction Stop

$vms = @()
try { $vms = Get-AzVM -Status -ErrorAction Stop } catch { $vms = @() }

$vmStateSummary = $vms |
    ForEach-Object {
        ($_.Statuses | Where-Object { $_.Code -like 'PowerState/*' } | Select-Object -First 1).DisplayStatus
    } |
    Group-Object | Sort-Object Count -Descending |
    ForEach-Object { [pscustomobject]@{ State = $_.Name; Count = $_.Count } }

$vnets = @()
try { $vnets = Get-AzVirtualNetwork -ErrorAction Stop } catch { $vnets = @() }

$pips = @()
try { $pips = Get-AzPublicIpAddress -ErrorAction Stop } catch { $pips = @() }

[pscustomobject]@{
    Check        = 'AzureSubscriptionInventory'
    Timestamp    = Get-Date
    TenantId     = $ctx.Tenant.Id
    Subscription = [pscustomobject]@{
        Id   = $ctx.Subscription.Id
        Name = $ctx.Subscription.Name
    }
    Counts = [pscustomobject]@{
        ResourceGroups    = $rgs.Count
        VirtualMachines   = @($vms).Count
        VirtualNetworks   = @($vnets).Count
        PublicIPAddresses = @($pips).Count
    }
    VMStateSummary = $vmStateSummary
}
