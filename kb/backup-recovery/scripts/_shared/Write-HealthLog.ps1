# _shared\Write-HealthLog.ps1
<#
.SYNOPSIS
Writes consistent, console-safe log entries for health check scripts.

.DESCRIPTION
Provides a single Write-HealthLog function to standardize:
- Console output
- Optional log file output
- Severity levels (INFO/WARN/ERROR/SUCCESS)
- Timestamped entries

Designed for use across backup/recovery scripts and orchestrators.

.PARAMETER Message
Log message text.

.PARAMETER Level
Log severity. Default is INFO.

.PARAMETER LogPath
Optional log file path. If provided, entries are appended.

.PARAMETER PassThru
If set, returns the written log line as a string.

.EXAMPLE
Write-HealthLog -Message "Starting backup checks" -Level INFO

.EXAMPLE
Write-HealthLog -Message "VSS Writer failed: SqlServerWriter" -Level ERROR -LogPath "C:\Reports\BackupHealth\run.log"

.NOTES
- Safe for production (read-only by default; writing only to provided LogPath).
- Avoids emojis/special characters for maximum compatibility in tooling and ticket systems.
#>

Set-StrictMode -Version Latest

function Write-HealthLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [ValidateSet('INFO','WARN','ERROR','SUCCESS')]
        [string]$Level = 'INFO',

        [string]$LogPath,

        [switch]$PassThru
    )

    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = "[{0}] [{1}] {2}" -f $ts, $Level, $Message

    # Console output (intentionally plain)
    Write-Host $line

    # Optional file append
    if ($LogPath) {
        $logDir = Split-Path -Path $LogPath -Parent
        if ($logDir -and -not (Test-Path -LiteralPath $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }

        Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    }

    if ($PassThru) {
        return $line
    }
}
