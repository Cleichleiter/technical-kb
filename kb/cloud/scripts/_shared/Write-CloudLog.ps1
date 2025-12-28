# kb\cloud\scripts\_shared\Write-CloudLog.ps1
<#
.SYNOPSIS
Writes structured log entries to console and (optionally) to a log file.

.DESCRIPTION
Standard logging helper for Cloud scripts. Produces consistent timestamped output.
Supports levels: INFO, WARN, ERROR, DEBUG.

.PARAMETER Message
Message to log.

.PARAMETER Level
Log level.

.PARAMETER Path
Optional file path to append logs to.

.PARAMETER PassThru
Returns the log entry object.

.EXAMPLE
Write-CloudLog -Message "Starting checks" -Level INFO

.EXAMPLE
Write-CloudLog -Message "Auth failed" -Level ERROR -Path C:\Reports\CloudHealth.log
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
    [string]$Message,

    [ValidateSet('INFO','WARN','ERROR','DEBUG')]
    [string]$Level = 'INFO',

    [string]$Path,

    [switch]$PassThru
)

$entry = [pscustomobject]@{
    TimeUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    Level   = $Level
    Message = $Message
}

$line = "{0} [{1}] {2}" -f $entry.TimeUtc, $entry.Level, $entry.Message

switch ($Level) {
    'ERROR' { Write-Error $line; break }
    'WARN'  { Write-Warning $line; break }
    'DEBUG' { Write-Host $line; break }
    default { Write-Host $line }
}

if ($Path) {
    try {
        $dir = Split-Path -Path $Path -Parent
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        Add-Content -LiteralPath $Path -Value $line -Encoding UTF8
    } catch {
        Write-Warning "Failed to write log to file: $Path. $($_.Exception.Message)"
    }
}

if ($PassThru) { return $entry }
