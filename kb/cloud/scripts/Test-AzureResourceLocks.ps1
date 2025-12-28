# Test-AzureResourceLocks.ps1
<#
.SYNOPSIS
Enumerates Azure resource locks and flags missing delete locks at subscription scope (best-effort).

.DESCRIPTION
Returns:
- Total locks (subscription)
- Locks by level (CanNotDelete, ReadOnly)
- Sample of resources without any lock (optional heuristic based on critical resource types)

.NOTES
Requires Az.Resources.
Read-only.
#>

[CmdletBinding()]
param(
    [string]$SubscriptionId,
    [int]$MaxUnlockedSample = 50
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$shared = Join-Path $PSScriptRoot '_shared'
. (Join-Path $shared 'Assert-Module.ps1')

Assert-Module -Name @('Az.Accounts','Az.Resources') | Out-Null

if ($SubscriptionId) {
    Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
}

$ctx = Get-AzContext -ErrorAction Stop
$scope = "/subscriptions/{0}" -f $ctx.Subscription.Id

$locks = Get-AzResourceLock -Scope $scope -ErrorAction SilentlyContinue
if (-not $locks) { $locks = @() }

$byLevel = $locks | Group-Object Level | Sort-Object Count -Descending |
    ForEach-Object { [pscustomobject]@{ Level = $_.Name; Count = $_.Count } }

# Heuristic: find "critical-ish" resources that have no lock at all
$criticalTypes = @(
    'Microsoft.Compute/virtualMachines',
    'Microsoft.KeyVault/vaults',
    'Microsoft.RecoveryServices/vaults',
    'Microsoft.Network/virtualNetworks',
    'Microsoft.Network/vpnGateways',
    'Microsoft.Network/azureFirewalls'
)

$resources = Get-AzResource -ErrorAction SilentlyContinue |
    Where-Object { $criticalTypes -contains $_.ResourceType }

$lockedIds = @($locks | ForEach-Object { $_.ResourceId }) | Where-Object { $_ }
$unlocked = $resources | Where-Object { $lockedIds -notcontains $_.ResourceId } |
    Select-Object -First $MaxUnlockedSample |
    Select-Object Name, ResourceGroupName, ResourceType, Location, ResourceId

[pscustomobject]@{
    Check        = 'AzureResourceLocks'
    Timestamp    = Get-Date
    Subscription = [pscustomobject]@{ Id = $ctx.Subscription.Id; Name = $ctx.Subscription.Name }
    TotalLocks   = $locks.Count
    LocksByLevel = $byLevel
    UnlockedCriticalResourcesSample = $unlocked
}
