<#
.SYNOPSIS
Lightweight logging helper for AD/DC health-check scripts.

.DESCRIPTION
Provides consistent console + optional file logging with severity levels.
Designed for read-only diagnostic scripts, but usable anywhere.

- Writes to console (Write-Host / Write-Warning / Write-Error).
- Optionally appends the same message to a log file.
- Supports structured fields to make logs easier to parse later.

.EXAMPLE
. "$PSScriptRoot\_shared\Write-HealthLog.ps1"
Write-HealthLog -Message "Starting replication checks" -Level INFO

.EXAMPLE
Write-HealthLog -Message "SYSVOL share missing" -Level ERROR -Path "C:\Temp\dc-health.log" -Tag "SYSVOL"

.NOTES
Author: Cheri Leichleiter (repo utility)
#>

Set-StrictMode -Version Latest

function Write-HealthLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO','WARN','ERROR','DEBUG')]
        [string]$Level = 'INFO',

        # Optional log file path. If provided, directory will be created if missing.
        [string]$Path,

        # Optional category/tag (e.g., REPL, DNS, SYSVOL, TIME)
        [string]$Tag,

        # Optional object for additional context (will be JSON-serialized for file logging)
        [object]$Data
    )

    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $tagPart   = if ([string]::IsNullOrWhiteSpace($Tag)) { '' } else { " [$Tag]" }

    $line = "[{0}] [{1}]{2} {3}" -f $timestamp, $Level, $tagPart, $Message

    # Console output
    switch ($Level) {
        'ERROR' { Write-Error   -Message $line; break }
        'WARN'  { Write-Warning -Message $line; break }
        'DEBUG' { Write-Verbose -Message $line; break }
        default { Write-Host $line }
    }

    # File output (optional)
    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        try {
            $dir = Split-Path -Parent $Path
            if ($dir -and -not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }

            if ($null -ne $Data) {
                # Write a second line for structured context (kept simple + parseable)
                $json = $Data | ConvertTo-Json -Depth 6 -Compress
                Add-Content -LiteralPath $Path -Value $line -Encoding UTF8
                Add-Content -LiteralPath $Path -Value ("[{0}] [DATA]{1} {2}" -f $timestamp, $tagPart, $json) -Encoding UTF8
            }
            else {
                Add-Content -LiteralPath $Path -Value $line -Encoding UTF8
            }
        }
        catch {
            # Don’t hard-fail a diagnostic run due to logging; emit warning and continue.
            Write-Warning ("[Write-HealthLog] Failed to write log file '{0}': {1}" -f $Path, $_.Exception.Message)
        }
    }
}
