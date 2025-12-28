# Get-M365ServiceHealth.ps1
<#
.SYNOPSIS
Retrieves Microsoft 365 service health (issues/advisories) using Microsoft Graph.

.DESCRIPTION
Uses Microsoft.Graph to query:
- /admin/serviceAnnouncement/healthOverviews
- /admin/serviceAnnouncement/issues (best-effort; requires appropriate permissions)

NOTES
Requires Microsoft.Graph module.
Requires Graph permissions. Typical: ServiceHealth.Read.All (application or delegated).
Read-only.
#>

[CmdletBinding()]
param(
    [switch]$ConnectIfNeeded
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
        Connect-MgGraph -Scopes @('ServiceHealth.Read.All') -ErrorAction Stop | Out-Null
    }
}

$health = $null
$issues = $null
$errors = New-Object System.Collections.Generic.List[string]

try {
    $health = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/admin/serviceAnnouncement/healthOverviews' -ErrorAction Stop
} catch {
    $errors.Add("Failed to query healthOverviews: $($_.Exception.Message)") | Out-Null
}

try {
    $issues = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/admin/serviceAnnouncement/issues?$top=50' -ErrorAction Stop
} catch {
    $errors.Add("Failed to query issues: $($_.Exception.Message)") | Out-Null
}

[pscustomobject]@{
    Check      = 'M365ServiceHealth'
    Timestamp  = Get-Date
    HealthOverviews = $health
    Issues          = $issues
    Errors          = $errors
}
