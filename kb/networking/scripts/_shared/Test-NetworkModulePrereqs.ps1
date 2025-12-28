<#
.SYNOPSIS
Validates required PowerShell modules and native networking capabilities.

.DESCRIPTION
Checks for required modules and core networking cmdlets used by
network diagnostics (NetTCPIP, DnsClient, NetSecurity, etc).

.PARAMETER RequiredModules
Modules to validate and import.

.PARAMETER FailOnMissing
If set, throws when a required module is missing.

.OUTPUTS
Object summarizing module and capability availability.

.NOTES
Read-only. Does not install modules.
#>

[CmdletBinding()]
param(
    [string[]]$RequiredModules = @(
        'NetTCPIP',
        'DnsClient',
        'NetSecurity'
    ),

    [switch]$FailOnMissing
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$results = New-Object System.Collections.Generic.List[object]

foreach ($module in $RequiredModules) {
    $found = Get-Module -ListAvailable -Name $module | Select-Object -First 1

    if ($found) {
        try {
            Import-Module $module -ErrorAction Stop | Out-Null
            $results.Add([pscustomobject]@{
                Module  = $module
                Status  = 'Loaded'
                Version = $found.Version
            }) | Out-Null
        } catch {
            if ($FailOnMissing) {
                throw "Module $module exists but failed to import: $($_.Exception.Message)"
            }
            $results.Add([pscustomobject]@{
                Module  = $module
                Status  = 'ImportFailed'
                Version = $found.Version
                Error   = $_.Exception.Message
            }) | Out-Null
        }
    } else {
        if ($FailOnMissing) {
            throw "Required module not found: $module"
        }
        $results.Add([pscustomobject]@{
            Module  = $module
            Status  = 'Missing'
            Version = $null
        }) | Out-Null
    }
}

[pscustomobject]@{
    Check      = 'NetworkModulePrereqs'
    Timestamp  = Get-Date
    Results    = $results
    HasErrors  = ($results | Where-Object { $_.Status -ne 'Loaded' }).Count -gt 0
}
