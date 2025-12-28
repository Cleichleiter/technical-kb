<#
.SYNOPSIS
Exports installed software inventory from registry uninstall keys (32-bit and 64-bit).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$OutputRoot,

    [Parameter()]
    [string]$LogPath,

    [Parameter()]
    [string]$ServerName = $env:COMPUTERNAME
)

$ErrorActionPreference = 'Stop'

function Write-LogLine { param([string]$Level,[string]$Message)
    if (Get-Command Write-MigrationLog -ErrorAction SilentlyContinue) { Write-MigrationLog -Level $Level -Message $Message -LogPath $LogPath }
    else { Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message" }
}

Write-LogLine INFO "Collecting installed software inventory..."

$paths = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

$apps = foreach ($p in $paths) {
    Get-ItemProperty -Path $p -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName } |
        Select-Object @{n='DisplayName';e={$_.DisplayName}},
                      @{n='DisplayVersion';e={$_.DisplayVersion}},
                      @{n='Publisher';e={$_.Publisher}},
                      @{n='InstallDate';e={$_.InstallDate}},
                      @{n='UninstallString';e={$_.UninstallString}},
                      @{n='InstallLocation';e={$_.InstallLocation}},
                      @{n='PSPath';e={$_.PSPath}}
}

$apps = $apps | Sort-Object DisplayName, DisplayVersion -Unique
$apps | Export-Csv -LiteralPath (Join-Path $OutputRoot '08-InstalledSoftware.csv') -NoTypeInformation

Write-LogLine INFO "Installed software inventory complete."
