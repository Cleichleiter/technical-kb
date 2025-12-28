<#
.SYNOPSIS
Ensures the current PowerShell session is running elevated.

.DESCRIPTION
Throws a terminating error if the session is not running as Administrator.
Designed to fail early and clearly in health check scripts.

.USAGE
Dot-source and call Assert-RunAsAdmin.

.NOTES
Does not attempt elevation. Validation only.
#>

Set-StrictMode -Version Latest

function Assert-RunAsAdmin {
    [CmdletBinding()]
    param(
        [string]$Message = 'This script must be run from an elevated PowerShell session (Run as Administrator).',
        [switch]$PassThru
    )

    try {
        $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        $isAdmin   = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        $isAdmin = $false
    }

    if (-not $isAdmin) {
        if ($PassThru) { return $false }
        throw $Message
    }

    if ($PassThru) { return $true }
}
