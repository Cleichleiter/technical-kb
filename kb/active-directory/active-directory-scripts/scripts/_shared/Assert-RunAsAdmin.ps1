<#
.SYNOPSIS
Ensures the current PowerShell session is running elevated (Run as Administrator).

.DESCRIPTION
Assert-RunAsAdmin is a small guardrail script intended to be dot-sourced by other scripts.
If the current session is not elevated, it throws a clear error message and stops execution.

WHEN TO USE
- At the start of scripts that query Security log, service configuration, registry under HKLM, or use tools that commonly require elevation.
- In orchestrators (Invoke-DCHealthCheck) to fail early with a readable message.

USAGE
Dot-source this script, then call Assert-RunAsAdmin.

.EXAMPLE
. "$PSScriptRoot\Assert-RunAsAdmin.ps1"
Assert-RunAsAdmin

.EXAMPLE
Assert-RunAsAdmin -Message "Run this DC health check from an elevated PowerShell session."
#>

Set-StrictMode -Version Latest

function Assert-RunAsAdmin {
    [CmdletBinding()]
    param(
        # Optional custom failure message
        [string]$Message = 'This script must be run from an elevated PowerShell session (Run as Administrator).',

        # If set, do not throw; return $false when not elevated
        [switch]$PassThru
    )

    $isAdmin = $false

    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p  = New-Object Security.Principal.WindowsPrincipal($id)
        $isAdmin = $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        # If we can't determine, treat as not elevated.
        $isAdmin = $false
    }

    if (-not $isAdmin) {
        if ($PassThru) { return $false }
        throw $Message
    }

    if ($PassThru) { return $true }
}
