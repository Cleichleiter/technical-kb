# Test-AzureConnectivity.ps1
<#
.SYNOPSIS
Validates Azure authentication and optional subscription context.

.DESCRIPTION
Ensures an Az context exists; prompts for interactive login if needed.
Optionally sets the subscription context.

.NOTES
Requires Az.Accounts.
Read-only.
#>

[CmdletBinding()]
param(
    [string]$TenantId,
    [string]$SubscriptionId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$shared = Join-Path $PSScriptRoot '_shared'
. (Join-Path $shared 'Assert-Module.ps1')

Assert-Module -Name @('Az.Accounts') | Out-Null

$ctx = $null
try { $ctx = Get-AzContext -ErrorAction Stop } catch { $ctx = $null }

if (-not $ctx) {
    if ($TenantId) { Connect-AzAccount -Tenant $TenantId -ErrorAction Stop | Out-Null }
    else { Connect-AzAccount -ErrorAction Stop | Out-Null }
    $ctx = Get-AzContext -ErrorAction Stop
}

if ($SubscriptionId) {
    Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
    $ctx = Get-AzContext -ErrorAction Stop
}

[pscustomobject]@{
    Check        = 'AzureConnectivity'
    Status       = 'PASS'
    Timestamp    = Get-Date
    TenantId     = $ctx.Tenant.Id
    Account      = $ctx.Account.Id
    Subscription = [pscustomobject]@{
        Id   = $ctx.Subscription.Id
        Name = $ctx.Subscription.Name
    }
}
