# Test-AzureRBAC.ps1
<#
.SYNOPSIS
Surfaces high-signal RBAC risks: owners, broad role assignments, and unknown principals.

.DESCRIPTION
Checks subscription-scoped role assignments for:
- Owners / Contributors counts
- Privileged roles at subscription scope
- Assignments with missing principal resolution (orphaned IDs)

.NOTES
Requires Az.Accounts, Az.Resources.
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

Assert-Module -Name @('Az.Accounts','Az.Resources') | Out-Null

if ($SubscriptionId) {
    Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
}

$ctx = Get-AzContext -ErrorAction Stop
$scope = "/subscriptions/{0}" -f $ctx.Subscription.Id

$assignments = Get-AzRoleAssignment -Scope $scope -ErrorAction Stop

$privRoles = @(
    'Owner',
    'Contributor',
    'User Access Administrator',
    'Role Based Access Control Administrator'
)

$priv = $assignments | Where-Object { $privRoles -contains $_.RoleDefinitionName }

$owners = $assignments | Where-Object { $_.RoleDefinitionName -eq 'Owner' }
$contributors = $assignments | Where-Object { $_.RoleDefinitionName -eq 'Contributor' }

# Orphan / unresolvable principals (best-effort)
$unknown = $assignments | Where-Object {
    [string]::IsNullOrWhiteSpace($_.DisplayName) -or [string]::IsNullOrWhiteSpace($_.SignInName)
} | Select-Object -First 500

$issues = New-Object System.Collections.Generic.List[string]
if ($owners.Count -gt 5) { $issues.Add("High number of subscription Owners detected ($($owners.Count)).") | Out-Null }
if ($unknown.Count -gt 0) { $issues.Add("Role assignments with missing principal resolution detected ($($unknown.Count)).") | Out-Null }

[pscustomobject]@{
    Check        = 'AzureRBAC'
    Timestamp    = Get-Date
    Subscription = [pscustomobject]@{ Id = $ctx.Subscription.Id; Name = $ctx.Subscription.Name }
    Counts = [pscustomobject]@{
        TotalAssignments = $assignments.Count
        Owners           = $owners.Count
        Contributors     = $contributors.Count
        PrivilegedAtSubScope = $priv.Count
        UnresolvedPrincipals = $unknown.Count
    }
    PrivilegedAssignmentsSample = $priv | Select-Object -First 50 |
        Select-Object RoleDefinitionName, DisplayName, SignInName, ObjectType, Scope
    UnresolvedAssignmentsSample = $unknown | Select-Object -First 50 |
        Select-Object RoleDefinitionName, ObjectId, ObjectType, Scope, DisplayName, SignInName
    HasIssues    = [bool]($issues.Count -gt 0)
    IssueReasons = $issues
}
