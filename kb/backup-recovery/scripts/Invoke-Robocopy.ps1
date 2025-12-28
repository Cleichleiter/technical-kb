# Invoke-Robocopy.ps1
<#
.SYNOPSIS
Wrapper script for Robocopy with safe defaults, structured logging, and repeatable execution.

.DESCRIPTION
Executes Robocopy using hardened, commonly accepted flags for:
- Large data sets
- Backup or migration scenarios
- Resumable, restart-safe copies
- Clear logging for audit and troubleshooting

This script does not delete destination data unless explicitly instructed.

.PARAMETER Source
Source directory path.

.PARAMETER Destination
Destination directory path.

.PARAMETER Mirror
If set, mirrors source to destination (/MIR).
WARNING: Deletes destination files not present in source.

.PARAMETER Threads
Number of Robocopy threads. Default is 16.

.PARAMETER LogPath
Optional path to write Robocopy log file.

.PARAMETER WhatIf
If set, runs Robocopy in list-only mode (/L).

.EXAMPLE
.\Invoke-Robocopy.ps1 -Source "D:\Data" -Destination "\\NAS01\Backups\Data"

.EXAMPLE
.\Invoke-Robocopy.ps1 -Source "D:\Shares" -Destination "E:\Shares" -Mirror -LogPath "C:\Logs\robocopy.log"

.NOTES
- Robocopy exit codes should be interpreted, not treated as simple success/failure.
- Exit codes 0–7 generally indicate success with varying conditions.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Source,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Destination,

    [switch]$Mirror,

    [ValidateRange(1,128)]
    [int]$Threads = 16,

    [string]$LogPath,

    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Validate paths
if (-not (Test-Path -LiteralPath $Source)) {
    throw "Source path does not exist: $Source"
}

if (-not (Test-Path -LiteralPath $Destination)) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
}

# Base robocopy options
$robocopyArgs = @(
    "`"$Source`""
    "`"$Destination`""
    '/E'            # Copy subdirectories, including empty ones
    '/Z'            # Restartable mode
    '/R:3'          # Retry count
    '/W:5'          # Wait between retries
    "/MT:$Threads"  # Multithreaded
    '/COPY:DAT'     # Data, attributes, timestamps
    '/DCOPY:T'      # Preserve directory timestamps
    '/NP'           # No progress (cleaner logs)
    '/TEE'          # Output to console + log
)

if ($Mirror) {
    $robocopyArgs += '/MIR'
}

if ($WhatIf) {
    $robocopyArgs += '/L'
}

if ($LogPath) {
    $logDir = Split-Path -Path $LogPath -Parent
    if ($logDir -and -not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $robocopyArgs += "/LOG:`"$LogPath`""
}

Write-Host "Starting Robocopy..."
Write-Host "Source:      $Source"
Write-Host "Destination: $Destination"
Write-Host "Threads:     $Threads"
Write-Host "Mirror:      $Mirror"
Write-Host "WhatIf:      $WhatIf"
if ($LogPath) { Write-Host "LogPath:     $LogPath" }
Write-Host ""

# Execute Robocopy
$exe = Get-Command robocopy.exe -ErrorAction Stop
& $exe.Source @robocopyArgs
$exitCode = $LASTEXITCODE

Write-Host ""
Write-Host "Robocopy completed with exit code: $exitCode"

# Exit code interpretation (documented behavior)
$result = switch ($exitCode) {
    { $_ -le 7 } { 'SUCCESS' }
    { $_ -le 15 } { 'WARNING' }
    default { 'FAILURE' }
}

[pscustomobject]@{
    Source      = $Source
    Destination = $Destination
    Mirror      = $Mirror
    Threads     = $Threads
    LogPath     = $LogPath
    WhatIf      = $WhatIf
    ExitCode    = $exitCode
    Result      = $result
}
