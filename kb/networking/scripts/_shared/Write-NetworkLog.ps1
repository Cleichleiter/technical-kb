<#
.SYNOPSIS
Writes standardized network diagnostic log entries.

.DESCRIPTION
Provides consistent logging for networking scripts.
Supports console output and optional file-based logging.

.PARAMETER Message
Log message text.

.PARAMETER Level
Severity level (INFO, WARN, ERROR, DEBUG).

.PARAMETER Path
Optional log file path.

.PARAMETER PassThru
Returns the log object to the pipeline.

.NOTES
Non-destructive. Safe for production.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Message,

    [ValidateSet('INFO','WARN','ERROR','DEBUG')]
    [string]$Level = 'INFO',

    [string]$Path,

    [switch]$PassThru
)

$timestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')

$entry = [pscustomobject]@{
    TimeUtc = $timestamp
    Level   = $Level
    Message = $Message
}

$line = "{0} [{1}] {2}" -f $timestamp, $Level, $Message

switch ($Level) {
    'ERROR' { Write-Error   $line; break }
    'WARN'  { Write-Warning $line; break }
    default { Write-Host   $line }
}

if ($Path) {
    $parent = Split-Path -Path $Path -Parent
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Add-Content -LiteralPath $Path -Value $line -Encoding UTF8
}

if ($PassThru) {
    $entry
}
