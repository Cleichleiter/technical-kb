<#
.SYNOPSIS
Creates a standardized report output folder for migration preflight runs.

.DESCRIPTION
Creates:
<Root>\reports\<ServerName>\Preflight_YYYYMMDD_HHMMSS\

Also returns a small object with commonly used paths to keep scripts consistent.

This helper does not require admin rights and does not depend on external modules.

.PARAMETER RootPath
The base path where the 'reports' folder should be created. Typically the section root (server-migrations).

.PARAMETER ServerName
The server name to use for the output folder. Defaults to the local computer name.

.PARAMETER Prefix
Folder prefix. Defaults to 'Preflight'.

.PARAMETER Timestamp
Optional timestamp string to force consistent naming across multiple scripts in a single run.

.EXAMPLE
. .\New-MigrationReportFolder.ps1
$run = New-MigrationReportFolder -RootPath $PSScriptRoot
$run.OutputRoot
#>

function New-MigrationReportFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,

        [Parameter()]
        [string]$ServerName = $env:COMPUTERNAME,

        [Parameter()]
        [string]$Prefix = 'Preflight',

        [Parameter()]
        [string]$Timestamp
    )

    if (-not (Test-Path -LiteralPath $RootPath)) {
        throw "RootPath does not exist: $RootPath"
    }

    if (-not $Timestamp) {
        $Timestamp = (Get-Date -Format 'yyyyMMdd_HHmmss')
    }

    $reportsRoot = Join-Path $RootPath 'reports'
    $serverRoot  = Join-Path $reportsRoot $ServerName
    $outputRoot  = Join-Path $serverRoot ("{0}_{1}" -f $Prefix, $Timestamp)

    $dirs = @($reportsRoot, $serverRoot, $outputRoot)

    foreach ($dir in $dirs) {
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir | Out-Null
        }
    }

    $logPath = Join-Path $outputRoot 'migration.log'

    [pscustomobject]@{
        RootPath    = $RootPath
        ReportsRoot = $reportsRoot
        ServerRoot  = $serverRoot
        OutputRoot  = $outputRoot
        LogPath     = $logPath
        ServerName  = $ServerName
        Prefix      = $Prefix
        Timestamp   = $Timestamp
    }
}
