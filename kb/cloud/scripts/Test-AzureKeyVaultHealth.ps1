<#
.SYNOPSIS
Checks Azure Key Vault configuration and health signals across the current subscription.

.DESCRIPTION
Enumerates Key Vaults and returns high-signal configuration details:
- Soft delete / purge protection (where exposed by the module/API version)
- Network access posture (PublicNetworkAccess, Network ACL default action/bypass)
- Access policy count (legacy model indicator)
- Enabled-for-* flags commonly used for deployment scenarios
- Basic secret/list permission test (optional)

WHEN TO USE
- Validating governance/security posture for Key Vaults
- Troubleshooting “cannot access secrets/certs” and access model confusion (RBAC vs access policies)
- Confirming purge protection/soft delete readiness prior to compliance reviews
- Fast inventory for migrations or environment assessments

.PARAMETER SubscriptionId
Optional subscription to target (sets context).

.PARAMETER IncludeAccessTest
Attempts a best-effort access test by listing secrets metadata (no secret values).
If access is denied, records the failure per vault.

.PARAMETER MaxSecretsToList
Maximum number of secret metadata items to list per vault when IncludeAccessTest is used.

.NOTES
- Read-only. Safe for production.
- Requires Az.KeyVault and Az.Accounts.
- Property availability varies by Az module versions and Key Vault API responses; this script captures best-effort fields.
#>

[CmdletBinding()]
param(
    [string]$SubscriptionId,
    [switch]$IncludeAccessTest,
    [ValidateRange(1,500)]
    [int]$MaxSecretsToList = 25
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$shared = Join-Path $PSScriptRoot '_shared'
. (Join-Path $shared 'Assert-Module.ps1')

Assert-Module -Name @('Az.Accounts','Az.Resources','Az.KeyVault') | Out-Null

if ($SubscriptionId) {
    Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
}

$ctx = Get-AzContext -ErrorAction Stop

$vaults = @()
try {
    $vaults = Get-AzKeyVault -ErrorAction Stop
} catch {
    $vaults = @()
}

$results = New-Object System.Collections.Generic.List[object]
$issues  = New-Object System.Collections.Generic.List[string]

foreach ($v in $vaults) {
    # Normalize property access (Az module/API versions vary)
    $propNames = $v.PSObject.Properties.Name

    $softDelete = if ($propNames -contains 'EnableSoftDelete') { $v.EnableSoftDelete } else { $null }
    $purgeProt  = if ($propNames -contains 'EnablePurgeProtection') { $v.EnablePurgeProtection } else { $null }

    $pna = if ($propNames -contains 'PublicNetworkAccess') { $v.PublicNetworkAccess } else { $null }

    $aclBypass = $null
    $aclDefault = $null
    $ipRules = $null
    $vnetRules = $null

    if ($propNames -contains 'NetworkAcls' -and $null -ne $v.NetworkAcls) {
        $aclBypass  = $v.NetworkAcls.Bypass
        $aclDefault = $v.NetworkAcls.DefaultAction
        $ipRules    = @($v.NetworkAcls.IpAddressRanges)
        $vnetRules  = @($v.NetworkAcls.VirtualNetworkResourceIds)
    }

    $apCount = if ($propNames -contains 'AccessPolicies') { @($v.AccessPolicies).Count } else { $null }

    # Optional access test: list secrets metadata (not values)
    $accessTest = $null
    if ($IncludeAccessTest) {
        try {
            $secrets = Get-AzKeyVaultSecret -VaultName $v.VaultName -ErrorAction Stop |
                Select-Object -First $MaxSecretsToList |
                Select-Object Name, Enabled, Expires, NotBefore, Created, Updated, Tags

            $accessTest = [pscustomobject]@{
                Status       = 'PASS'
                SecretCount  = @($secrets).Count
                Secrets      = $secrets
                Error        = $null
            }
        } catch {
            $accessTest = [pscustomobject]@{
                Status       = 'FAIL'
                SecretCount  = $null
                Secrets      = $null
                Error        = $_.Exception.Message
            }
        }
    }

    # Issue flags (best-effort)
    if ($purgeProt -eq $false) { $issues.Add("Vault without purge protection: $($v.VaultName)") | Out-Null }

    $results.Add([pscustomobject]@{
        Name                  = $v.VaultName
        ResourceGroupName     = $v.ResourceGroupName
        Location              = $v.Location
        Sku                   = $v.Sku.Name

        EnabledForDeployment          = $v.EnabledForDeployment
        EnabledForTemplateDeployment  = $v.EnabledForTemplateDeployment
        EnabledForDiskEncryption      = $v.EnabledForDiskEncryption

        EnableSoftDelete       = $softDelete
        EnablePurgeProtection  = $purgeProt

        PublicNetworkAccess    = $pna
        NetworkAclsBypass      = $aclBypass
        NetworkAclsDefaultAction = $aclDefault
        IpRuleCount            = if ($null -ne $ipRules)  { @($ipRules).Count } else { $null }
        VnetRuleCount          = if ($null -ne $vnetRules){ @($vnetRules).Count } else { $null }

        AccessPoliciesCount    = $apCount

        AccessTest             = $accessTest
    }) | Out-Null
}

[pscustomobject]@{
    Check        = 'AzureKeyVaultHealth'
    Timestamp    = Get-Date
    Subscription = [pscustomobject]@{
        Id   = $ctx.Subscription.Id
        Name = $ctx.Subscription.Name
        TenantId = $ctx.Tenant.Id
    }
    VaultCount   = @($results).Count
    Vaults       = $results
    HasIssues    = [bool]($issues.Count -gt 0)
    IssueReasons = $issues
}
