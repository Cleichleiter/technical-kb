<#
.SYNOPSIS
Summarizes recent critical/error events relevant to migration risk (disk, NTFS, SMB, VSS, auth signals).

.PARAMETER LookbackDays
How far back to search event logs.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$OutputRoot,

    [Parameter()]
    [string]$LogPath,

    [Parameter()]
    [ValidateRange(1,90)]
    [int]$LookbackDays = 7,

    [Parameter()]
    [string]$ServerName = $env:COMPUTERNAME
)

$ErrorActionPreference = 'Stop'

function Write-LogLine { param([string]$Level,[string]$Message)
    if (Get-Command Write-MigrationLog -ErrorAction SilentlyContinue) { Write-MigrationLog -Level $Level -Message $Message -LogPath $LogPath }
    else { Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message" }
}

Write-LogLine INFO "Collecting migration risk event log summary (last $LookbackDays days)..."

$start = (Get-Date).AddDays(-1 * $LookbackDays)

# Focused providers/logs that frequently correlate with migration issues
$targets = @(
    @{ Log='System'; Provider='disk' },
    @{ Log='System'; Provider='Ntfs' },
    @{ Log='System'; Provider='volsnap' },
    @{ Log='System'; Provider='Microsoft-Windows-SMBServer' },
    @{ Log='System'; Provider='Microsoft-Windows-SMBClient' },
    @{ Log='System'; Provider='Microsoft-Windows-Time-Service' },
    @{ Log='System'; Provider='Microsoft-Windows-Kerberos-Key-Distribution-Center' },
    @{ Log='Application'; Provider='VSS' }
)

$rows = New-Object System.Collections.Generic.List[object]

foreach ($t in $targets) {
    try {
        $events = Get-WinEvent -FilterHashtable @{
            LogName      = $t.Log
            ProviderName = $t.Provider
            StartTime    = $start
        } -ErrorAction Stop

        # Keep only Error/Critical by display name where possible
        $events = $events | Where-Object { $_.LevelDisplayName -in @('Critical','Error') }

        foreach ($e in $events) {
            $rows.Add([pscustomobject]@{
                TimeCreated = $e.TimeCreated
                LogName     = $t.Log
                Provider    = $t.Provider
                Id          = $e.Id
                Level       = $e.LevelDisplayName
                Message     = $e.Message
            })
        }
    } catch {
        continue
    }
}

$outCsv = Join-Path $OutputRoot '13-MigrationRiskEvents.csv'
$rows | Sort-Object TimeCreated -Descending | Export-Csv -LiteralPath $outCsv -NoTypeInformation

$summary = [pscustomobject]@{
    ServerName   = $ServerName
    LookbackDays = $LookbackDays
    EventCount   = $rows.Count
}
$summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutputRoot '13-MigrationRiskEventsSummary.json') -Encoding UTF8

Write-LogLine INFO "Event log risk summary complete."
