# _shared\Assert-RunAsAdmin.ps1
<#
.SYNOPSIS
Ensures the current PowerShell session is running elevated.

.DESCRIPTION
Provides Assert-RunAsAdmin to enforce elevation for checks that require it.

.PARAMETER Message
Custom error message to display if not elevated.

.PARAMETER ReturnBoolean
If set, returns $true/$false instead of throwing.

.EXAMPLE
Assert-RunAsAdmin

.EXAMPLE
if (-not (Assert-RunAsAdmin -ReturnBoolean)) { return }

.NOTES
Use this in scripts that query protected logs, system services, VSS writers, or require privileged access.
#>

Set-StrictMode -Version Latest

function Assert-RunAsAdmin {
    [CmdletBinding()]
    param(
        [string]$Message = 'This script must be run as Administrator.',
        [switch]$ReturnBoolean
    )

    $isAdmin = $false
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p  = New-Object Security.Principal.WindowsPrincipal($id)
        $isAdmin = $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        $isAdmin = $false
    }

    if ($ReturnBoolean) {
        return $isAdmin
    }

    if (-not $isAdmin) {
        throw $Message
    }

    return $true
}
