# Test-AzureBackupHealth.ps1
<#
.SYNOPSIS
Inventories Recovery Services vaults and backup items (high-level) for stale/failed protection signals.

.DESCRIPTION
Returns:
- Vault inventory
- Backup item counts (best-effort)
- Recent jobs (optional) if module supports it

.NOTES
Requires Az.RecoveryServices.
Read-only.
#>

[CmdletBinding()]
param(
    [string]$SubscriptionId,
    [int]$MaxJobs = 50
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$shared = Join-Path $PSScriptRoot '_shared'
. (Join-Path $shared 'Assert-Module.ps1')

Assert-Module -Name @('Az.Accounts','Az.RecoveryServices') | Out-Null

if ($SubscriptionId) {
    Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
}

$ctx = Get-AzContext -ErrorAction Stop

$vaults = @()
try { $vaults = Get-AzRecoveryServicesVault -ErrorAction Stop } catch { $vaults = @() }

$vaultResults = New-Object System.Collections.Generic.List[object]

foreach ($v in $vaults) {
    try {
        Set-AzRecoveryServicesVaultContext -Vault $v -ErrorAction Stop | Out-Null

        $items = @()
        try {
            $items = Get-AzRecoveryServicesBackupItem -ErrorAction Stop
        } catch {
            $items = @()
        }

        $jobs = @()
        try {
            $jobs = Get-AzRecoveryServicesBackupJob -ErrorAction Stop |
                Sort-Object StartTime -Descending |
                Select-Object -First $MaxJobs
        } catch {
            $jobs = @()
        }

        $vaultResults.Add([pscustomobject]@{
            VaultName        = $v.Name
            ResourceGroup    = $v.ResourceGroupName
            Location         = $v.Location
            BackupItemCount  = @($items).Count
            BackupItemsSample = $items | Select-Object -First 25 |
                Select-Object Name, WorkloadType, ProtectionStatus, HealthStatus, ContainerName
            JobsSample = $jobs | Select-Object -First 25 |
                Select-Object Operation, Status, StartTime, EndTime
        }) | Out-Null
    } catch {
        $vaultResults.Add([pscustomobject]@{
            VaultName     = $v.Name
            ResourceGroup = $v.ResourceGroupName
            Location      = $v.Location
            Error         = $_.Exception.Message
        }) | Out-Null
    }
}

[pscustomobject]@{
    Check        = 'AzureBackupHealth'
    Timestamp    = Get-Date
    Subscription = [pscustomobject]@{ Id = $ctx.Subscription.Id; Name = $ctx.Subscription.Name }
    VaultCount   = @($vaultResults).Count
    Vaults       = $vaultResults
