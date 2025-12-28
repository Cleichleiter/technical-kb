<#
.SYNOPSIS
Standardized logging helper for Windows health check scripts.

.DESCRIPTION
Provides consistent console and optional file logging with severity levels.
Designed for read-only diagnostics and orchestration scripts.

- Writes structured, timestamped messages
- Supports INFO, WARN, ERROR, DEBUG levels
- Optional file logging with automatic directory creation
- Optional structured data payload (JSON)

.USAGE
Dot-source this script and call Write-HealthLog.

.NOTES
Safe for production. Does not modify system state.
#>

Set-StrictMode -Version Latest

function Write-HealthLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO','WARN','ERROR','DEBUG')]
        [string]$Level = 'INFO',

        [string]$Path,
        [string]$Tag,
        [object]$Data
    )

    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $tagText   = if ($Tag) { " [$Tag]" } else { '' }
    $line      = "[{0}] [{1}]{2} {3}" -f $timestamp, $Level, $tagText, $Message

    switch ($Level) {
        'ERROR' { Write-Error   $line }
        'WARN'  { Write-Warning $line }
        'DEBUG' { Write-Verbose $line }
        default { Write-Host    $line }
    }

    if ($Path) {
        try {
            $dir = Split-Path -Parent $Path
            if ($dir -and -not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }

            Add-Content -LiteralPath $Path -Value $line -Encoding UTF8

            if ($null -ne $Data) {
                $json = $Data | ConvertTo-Json -Depth 6 -Compress
                Add-Content -LiteralPath $Path -Value "[{0}] [DATA]{1} {2}" -f $timestamp, $tagText, $json
            }
        }
        catch {
            Write-Warning "Failed to write log file '$Path': $($_.Exception.Message)"
        }
    }
}
