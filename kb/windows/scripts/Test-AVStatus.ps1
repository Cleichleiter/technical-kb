# Test-AVStatus.ps1
<#
.SYNOPSIS
Detects installed antivirus products and reports basic health/status where available.

.DESCRIPTION
Uses SecurityCenter2 (client OS) and best-effort fallbacks (services/registry) for servers.
Collects:
- Registered AV products (name, path, state) when SecurityCenter2 is available
- Common AV-related services presence/running state
- Notes when AV detection is limited due to OS role/version

WHEN TO USE
- Incident response triage
- Baseline security validation
- Troubleshooting conflicts between endpoint security products
- Verifying third-party AV is present on servers

NOTES
Read-only.
SecurityCenter2 is typically present on client OS, not on Windows Server.
#>

[CmdletBinding()]
param(
    [switch]$IncludeServiceScan
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Try-QuerySecurityCenter2 {
    try {
        Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop |
            ForEach-Object {
                [pscustomobject]@{
                    DisplayName     = $_.displayName
                    PathToExe       = $_.pathToSignedProductExe
                    PathToReporting = $_.pathToSignedReportingExe
                    ProductState    = $_.productState
                    Timestamp       = Get-Date
                }
            }
    } catch {
        @(
            [pscustomobject]@{
                Note = "SecurityCenter2 query not available or failed: $($_.Exception.Message)"
            }
        )
    }
}

function Get-ServiceInfo {
    param([Parameter(Mandatory)][string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyCo
