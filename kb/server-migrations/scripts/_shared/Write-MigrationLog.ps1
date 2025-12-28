<#
.SYNOPSIS
Writes standardized log lines to the console and (optionally) to a log file.

.DESCRIPTION
Provides consistent logging across server-migration scripts. Designed to be safe when pasted into
interactive consoles and to avoid dependencies on external modules.

Log format:
YYYY-MM-DD HH:MM:SS [LEVEL] Message

Levels:
INFO, WARN, ERROR, DEBUG

.EXAMPLE
. .\Write-MigrationLog.ps1
Write-MigrationLog -Level INFO -Message "Starting preflight" -LogPath $LogPath

.EXAMPLE
Write-MigrationLog -Level ERROR -Message "Failed to query SMB shares" -LogPath $LogPath -PassThru
#>

function Write-MigrationLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('INFO','WARN','ERROR','DEBUG')]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [string]$LogPath,

        [Parameter()]
        [switch]$PassThru
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "$timestamp [$Level] $Message"

    # Console output
    Write-Host $line

    # File output (optional)
    if ($LogPath) {
        $parent = Split-Path -Parent $LogPath
        if ($parent -and (-not (Test-Path -LiteralPath $parent))) {
            New-Item -ItemType Directory -Path $parent | Out-Null
        }

        if (-not (Test-Path -LiteralPath $LogPath)) {
            New-Item -ItemType File -Path $LogPath | Out-Null
        }

        Add-Content -LiteralPath $LogPath -Value $line
    }

    if ($PassThru) {
        return $line
    }
}
