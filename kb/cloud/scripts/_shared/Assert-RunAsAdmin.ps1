# kb\cloud\scripts\_shared\Assert-RunAsAdmin.ps1
<#
.SYNOPSIS
Ensures the current PowerShell session is running elevated.

.DESCRIPTION
Some Cloud checks (certificate store access, certain modules, local report paths) may require elevation.
This helper throws a terminating error if not elevated unless -WarnOnly is used.

.PARAMETER WarnOnly
Only warns instead of throwing.

.EXAMPLE
. .\_shared\Assert-RunAsAdmin.ps1
Assert-RunAsAdmin

.EXAMPLE
Assert-RunAsAdmin -WarnOnly
#>

function Assert-RunAsAdmin {
    [CmdletBinding()]
    param(
        [switch]$WarnOnly
    )

    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        $msg = 'This script should be run in an elevated PowerShell session (Run as Administrator).'
        if ($WarnOnly) {
            Write-Warning $msg
            return $false
        }
        throw $msg
    }

    return $true
}
