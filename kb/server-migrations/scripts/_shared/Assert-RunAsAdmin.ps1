<#
.SYNOPSIS
Ensures the current PowerShell session is running with elevated (Administrator) privileges.

.DESCRIPTION
Many migration discovery actions require admin rights (SMB sessions, open files, services, scheduled tasks).
This helper throws a terminating error if the session is not elevated, so calling scripts fail fast.

.EXAMPLE
. .\Assert-RunAsAdmin.ps1
Assert-RunAsAdmin
#>

function Assert-RunAsAdmin {
    [CmdletBinding()]
    param()

    try {
        $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        $isAdmin   = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

        if (-not $isAdmin) {
            throw "This script must be run in an elevated PowerShell session (Run as Administrator)."
        }
    }
    catch {
        throw $_
    }
}
