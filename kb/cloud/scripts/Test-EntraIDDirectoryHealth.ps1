# Test-EntraIDDirectoryHealth.ps1
<#
.SYNOPSIS
Collects basic Entra ID (Azure AD) directory health signals using Microsoft Graph.

.DESCRIPTION
Returns:
- Tenant organization info (display name, verified domains)
- Directory roles enabled (best-effort)
- Counts for users/groups (best-effort; can be slow in large tenants)

NOTES
Requires Microsoft.Graph.
Requires Graph permissions. Typical: Directory.Read.All (delegated) or equivalent.
Read-only.
#>

[CmdletBinding()]
param(
    [switch]$ConnectIfNeeded,
    [switch]$IncludeCounts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$shared = Join-Path $PSScriptRoot '_shared'
. (Join-Path $shared 'Assert-Module.ps1')

Assert-Module -Name @('Microsoft.Graph.Authentication') | Out-Null

if ($ConnectIfNeeded) {
    try {
        $ctx = Get-MgContext -ErrorAction Stop
        if (-not $ctx) { throw "No Graph context" }
    } catch {
        Connect-MgGraph -Scopes @('Directory.Read.All') -ErrorAction Stop | Out-Null
    }
}

$errors = New-Object System.Collections.Generic.List[string]

$org = $null
try { $org = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/organization' -ErrorAction Stop } catch { $errors.Add($_.Exception.Message) | Out-Null }

$roles = $null
try { $roles = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/directoryRoles' -ErrorAction Stop } catch { $errors.Add($_.Exception.Message) | Out-Null }

$userCount = $null
$groupCount = $null
if ($IncludeCounts) {
    try { $userCount = (Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/users?$top=1&$count=true' -Headers @{ ConsistencyLevel = 'eventual' } -ErrorAction Stop).'@odata.count' } catch { $errors.Add("User count failed: $($_.Exception.Message)") | Out-Null }
    try { $groupCount = (Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/groups?$top=1&$count=true' -Headers @{ ConsistencyLevel = 'eventual' } -ErrorAction Stop).'@odata.count' } catch { $errors.Add("Group count failed: $($_.Exception.Message)") | Out-Null }
}

[pscustomobject]@{
    Check     = 'EntraIDDirectoryHealth'
    Timestamp = Get-Date
    Organization = $org
    DirectoryRoles = $roles
    Counts = if ($IncludeCounts) {
        [pscustomobject]@{ Users = $userCount; Groups = $groupCount }
    } else { $null }
    Errors = $errors
}
