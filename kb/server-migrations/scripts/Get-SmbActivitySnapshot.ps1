<#
.SYNOPSIS
Captures SMB sessions and open files to estimate cutover impact and locked-file risk.
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

Write-LogLine INFO "Collecting SMB sessions and open files..."

$sessions = @()
$openFiles = @()

try { $sessions = Get-SmbSession | Select-Object ClientComputerName, ClientUserName, NumOpens, Dialect, SessionId } catch { }
try { $openFiles = Get-SmbOpenFile | Select-Object ClientComputerName, ClientUserName, Path, SessionId, FileId } catch { }

if ($sessions)  { $sessions  | Export-Csv -LiteralPath (Join-Path $OutputRoot '05-SmbSessions.csv') -NoTypeInformation }
if ($openFiles) { $openFiles | Export-Csv -LiteralPath (Join-Path $OutputRoot '05-SmbOpenFiles.csv') -NoTypeInformation }

$summary = [pscustomobject]@{
    ServerName    = $ServerName
    SessionCount  = @($sessions).Count
    OpenFileCount = @($openFiles).Count
}
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputRoot '05-SmbActivitySummary.json') -Encoding UTF8

Write-LogLine INFO "SMB activity snapshot complete."
