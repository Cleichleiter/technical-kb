<#
.SYNOPSIS
Captures backup/VSS readiness signals and related system indicators.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$OutputRoot,

    [Parameter()]
    [string]$LogPath,

    [Parameter()]
    [int]$EventLookbackDays = 14,

    [Parameter()]
    [string]$ServerName = $env:COMPUTERNAME
)

$ErrorActionPreference = 'Stop'

function Write-LogLine { param([string]$Level,[string]$Message)
    if (Get-Command Write-MigrationLog -ErrorAction SilentlyContinue) { Write-MigrationLog -Level $Level -Message $Message -LogPath $LogPath }
    else { Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message" }
}

Write-LogLine INFO "Collecting backup and VSS readiness snapshot..."

# VSS writers
$vssWritersPath = Join-Path $OutputRoot '09-VSS-Writers.txt'
try {
    $writers = & vssadmin list writers 2>&1
    $writers | Set-Content -LiteralPath $vssWritersPath -Encoding UTF8
} catch {
    "vssadmin list writers failed: $($_.Exception.Message)" | Set-Content -LiteralPath $vssWritersPath -Encoding UTF8
}

# Shadow storage
$vssShadowPath = Join-Path $OutputRoot '09-VSS-ShadowStorage.txt'
try {
    $shadow = & vssadmin list shadowstorage 2>&1
    $shadow | Set-Content -LiteralPath $vssShadowPath -Encoding UTF8
} catch {
    "vssadmin list shadowstorage failed: $($_.Exception.Message)" | Set-Content -LiteralPath $vssShadowPath -Encoding UTF8
}

# Event logs signals (backup/vss)
$start = (Get-Date).AddDays(-1 * $EventLookbackDays)

$signals = New-Object System.Collections.Generic.List[object]
$logQueries = @(
    @{ Log='Application'; Provider='Microsoft-Windows-Backup'; Label='Windows Backup' },
    @{ Log='Application'; Provider='VSS'; Label='VSS' },
    @{ Log='System';      Provider='volsnap'; Label='Volume Snapshot Driver' }
)

foreach ($q in $logQueries) {
    try {
        $events = Get-WinEvent -FilterHashtable @{ LogName=$q.Log; ProviderName=$q.Provider; StartTime=$start } -ErrorAction Stop |
            Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, LogName, Message

        foreach ($e in $events) {
            $signals.Add([pscustomobject]@{
                Label   = $q.Label
                Time    = $e.TimeCreated
                Id      = $e.Id
                Level   = $e.LevelDisplayName
                Provider= $e.ProviderName
                Log     = $e.LogName
                Message = $e.Message
            })
        }
    } catch {
        continue
    }
}

$signals | Export-Csv -LiteralPath (Join-Path $OutputRoot '09-BackupVssSignals.csv') -NoTypeInformation

# Summary JSON
$summary = [pscustomobject]@{
    ServerName         = $ServerName
    LookbackDays       = $EventLookbackDays
    SignalsCount       = $signals.Count
    WritersCaptured    = (Test-Path -LiteralPath $vssWritersPath)
    ShadowStorageCaptured = (Test-Path -LiteralPath $vssShadowPath)
}
$summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutputRoot '09-BackupReadinessSummary.json') -Encoding UTF8

Write-LogLine INFO "Backup/VSS readiness snapshot complete."
