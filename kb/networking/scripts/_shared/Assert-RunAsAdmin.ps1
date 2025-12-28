<#
.SYNOPSIS
Ensures the current PowerShell session is running elevated.

.DESCRIPTION
Validates administrator context. Can throw or warn-only.

.PARAMETER WarnOnly
If set, emits a warning instead of throwing.

.NOTES
Used by scripts that inspect firewall state, IPSec, adapters, or system services.
#>

function Assert-RunAsAdmin {
    [CmdletBinding()]
    param(
        [switch]$WarnOnly
    )

    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)

    $isAdmin = $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )

    if (-not $isAdmin) {
        $msg = 'This script requires an elevated PowerShell session (Run as Administrator).'
        if ($WarnOnly) {
            Write-Warning $msg
            return $false
        }
        throw $msg
    }

    $true
}
