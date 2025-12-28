# Test-AzurePolicyCompliance.ps1
<#
.SYNOPSIS
Collects a top-level Azure Policy compliance snapshot.

.DESCRIPTION
Returns policy state summary for the current subscription:
- Total noncompliant states (best-effort)
- Top noncompliant policy definitions (by count)

.NOTES
Requires Az.PolicyInsights.
Read-only.
#>

[CmdletBinding()]
param(
    [string]$SubscriptionId,
    [int]$Top = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$shared = Join-Path $PSScriptRoot '_shared'
. (Join-Path $shared 'Assert-Module.ps1')

Assert-Module -Name @('Az.Accounts','Az.PolicyInsights') | Out-Null

if ($SubscriptionId) {
    Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
}

$ctx = Get-AzContext -ErrorAction Stop
$scope = "/subscriptions/{0}" -f $ctx.Subscription.Id

# Policy states (noncompliant)
$states = @()
try {
    $states = Get-AzPolicyState -Scope $scope -Filter "ComplianceState eq 'NonCompliant'" -ErrorAction Stop
} catch {
    # Some tenants restrict Policy Insights or older modules behave differently
    $states = @()
}

$topDefs = $states |
    Group-Object PolicyDefinitionName |
    Sort-Object Count -Descending |
    Select-Object -First $Top |
    ForEach-Object { [pscustomobject]@{ PolicyDefinitionName = $_.Name; NonCompliantCount = $_.Count } }

[pscustomobject]@{
    Check        = 'AzurePolicyCompliance'
    Timestamp    = Get-Date
    Subscription = [pscustomobject]@{ Id = $ctx.Subscription.Id; Name = $ctx.Subscription.Name }
    NonCompliantStateCount = @($states).Count
    TopNonCompliantPolicyDefinitions = $topDefs
    Note = if ($states.Count -eq 0) { 'No noncompliant states returned (may be fully compliant, restricted access, or Policy Insights not enabled).' } else { $null }
}
