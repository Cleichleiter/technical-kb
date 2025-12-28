<#
.SYNOPSIS
Captures print server inventory (printers, ports, drivers) if PrintManagement tools are available.
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

Write-LogLine INFO "Collecting print server inventory..."

$outNote = Join-Path $OutputRoot '12-Print-Notes.txt'

$hasPrint = $false
try {
    Import-Module PrintManagement -ErrorAction Stop
    $hasPrint = $true
} catch {
    $hasPrint = $false
}

if (-not $hasPrint) {
    "PrintManagement module not available. If this server is a print server, install print management tools or run from a host with PrintManagement cmdlets." |
        Set-Content -LiteralPath $outNote -Encoding UTF8
    Write-LogLine INFO "Print tools not present; wrote note."
    return
}

$printers = Get-Printer | Select-Object Name, ShareName, Shared, Published, DriverName, PortName, Comment, Location
$ports    = Get-PrinterPort | Select-Object Name, PrinterHostAddress, PortNumber, Protocol, Description
$drivers  = Get-PrinterDriver | Select-Object Name, Manufacturer, MajorVersion, MinorVersion, DriverPath, InfPath

$printers | Export-Csv -LiteralPath (Join-Path $OutputRoot '12-Printers.csv') -NoTypeInformation
$ports    | Export-Csv -LiteralPath (Join-Path $OutputRoot '12-PrintPorts.csv') -NoTypeInformation
$drivers  | Export-Csv -LiteralPath (Join-Path $OutputRoot '12-PrintDrivers.csv') -NoTypeInformation

Write-LogLine INFO "Print server inventory complete."
