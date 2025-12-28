# kb\cloud\scripts\_shared\Assert-Module.ps1
<#
.SYNOPSIS
Validates required PowerShell modules are installed and importable.

.DESCRIPTION
For Cloud scripts, common dependencies include:
- Az.Accounts / Az.Resources (Azure)
- Microsoft.Graph (Entra ID / M365)
- ExchangeOnlineManagement (Exchange checks)

This helper validates modules and can optionally attempt to install missing modules.

.PARAMETER Name
One or more module names.

.PARAMETER MinimumVersion
Optional minimum version.

.PARAMETER InstallIfMissing
Attempts to install from PSGallery if missing.

.PARAMETER Scope
Install scope (CurrentUser recommended for workstations).

.EXAMPLE
Assert-Module -Name Az.Accounts, Az.Resources

.EXAMPLE
Assert-Module -Name Az.Accounts -MinimumVersion 2.13.0 -InstallIfMissing
#>

function Assert-Module {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string[]]$Name,

        [string]$MinimumVersion,

        [switch]$InstallIfMissing,

        [ValidateSet('CurrentUser','AllUsers')]
        [string]$Scope = 'CurrentUser'
    )

    foreach ($n in $Name) {
        $available = Get-Module -ListAvailable -Name $n | Sort-Object Version -Descending | Select-Object -First 1

        if (-not $available) {
            if ($InstallIfMissing) {
                Install-Module -Name $n -Scope $Scope -Force -ErrorAction Stop
                $available = Get-Module -ListAvailable -Name $n | Sort-Object Version -Descending | Select-Object -First 1
            } else {
                throw "Required module not found: $n. Install it (Install-Module $n) or run with -InstallIfMissing where supported."
            }
        }

        if ($MinimumVersion) {
            $min = [version]$MinimumVersion
            $ver = [version]$available.Version
            if ($ver -lt $min) {
                throw "Module $n version $ver is below required minimum $min."
            }
        }

        Import-Module -Name $n -ErrorAction Stop | Out-Null
    }

    return $true
}
