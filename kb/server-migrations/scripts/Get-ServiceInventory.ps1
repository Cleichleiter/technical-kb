<#
.SYNOPSIS
Exports Windows services inventory including run-as identities and binary paths.
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

Write-LogLine INFO "Collecting services inventory..."

$services = Get-CimInstance Win32_Service | Select-Object `
    Name, DisplayName, State, StartMode, StartName, PathName, ServiceType

$services | Export-Csv -LiteralPath (Join-Path $OutputRoot '06-Services.csv') -NoTypeInformation

Write-LogLine INFO "Services inventory complete."
