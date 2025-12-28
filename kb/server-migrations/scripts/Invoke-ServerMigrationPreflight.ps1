<#
.SYNOPSIS
Runs a standard server migration preflight data collection and writes outputs to a timestamped folder.

.DESCRIPTION
This orchestrator creates a reports folder under the server-migrations section root and calls each
collector script with the same OutputRoot and LogPath.

Outputs are designed to be attached to tickets/change records and used for cutover planning.

.NOTES
- Designed for local execution on the source server.
- Some collectors require admin (SMB sessions/open files, services, scheduled tasks, etc.).
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ServerName = $env:COMPUTERNAME,

    [Parameter()]
    [ValidateSet('Preflight','Discovery','Assessment')]
    [string]$Prefix = 'Preflight',

    [Parameter()]
    [string]$RootPath
)

$ErrorActionPreference = 'Stop'

# Resolve section root (kb\server-migrations)
if (-not $RootPath) {
    # This script lives in: ...\server-migrations\scripts
    $scriptsRoot = $PSScriptRoot
    $RootPath = Split-Path -Parent $scriptsRoot
}

$sharedRoot = Join-Path $PSScriptRoot '_shared'

# Dot-source shared helpers
. (Join-Path $sharedRoot 'Assert-RunAsAdmin.ps1')
. (Join-Path $sharedRoot 'Write-MigrationLog.ps1')
. (Join-Path $sharedRoot 'New-MigrationReportFolder.ps1')

# Require admin for full fidelity
Assert-RunAsAdmin

$run = New-MigrationReportFolder -RootPath $RootPath -ServerName $ServerName -Prefix $Prefix
$logPath = $run.LogPath

Write-MigrationLog -Level INFO -Message "Starting server migration preflight for: $ServerName" -LogPath $logPath
Write-MigrationLog -Level INFO -Message "OutputRoot: $($run.OutputRoot)" -LogPath $logPath

# Write run metadata
$runInfo = [pscustomobject]@{
    ServerName    = $ServerName
    Prefix        = $Prefix
    Timestamp     = $run.Timestamp
    RootPath      = $run.RootPath
    OutputRoot    = $run.OutputRoot
    StartedUtc    = (Get-Date).ToUniversalTime().ToString('o')
    StartedLocal  = (Get-Date).ToString('o')
    User          = "$env:USERDOMAIN\$env:USERNAME"
    Computer      = $env:COMPUTERNAME
    PSVersion     = $PSVersionTable.PSVersion.ToString()
}
$runInfo | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $run.OutputRoot '00-RunInfo.json') -Encoding UTF8

# Collector list (file name, friendly name)
$collectors = @(
    @{ File='Get-ServerPlatformSummary.ps1';      Name='Platform summary' }
    @{ File='Get-ServerStorageInventory.ps1';     Name='Storage inventory' }
    @{ File='Get-FileShareInventory.ps1';         Name='File shares' }
    @{ File='Export-NtfsAclSnapshot.ps1';         Name='NTFS ACL snapshot' }
    @{ File='Get-SmbActivitySnapshot.ps1';        Name='SMB activity snapshot' }
    @{ File='Get-ServiceInventory.ps1';           Name='Services inventory' }
    @{ File='Get-ScheduledTaskExport.ps1';        Name='Scheduled tasks' }
    @{ File='Get-InstalledSoftwareInventory.ps1'; Name='Installed software' }
    @{ File='Test-BackupReadinessSnapshot.ps1';   Name='Backup/VSS readiness' }
    @{ File='Get-DfsConfigurationSnapshot.ps1';   Name='DFS configuration (if present)' }
    @{ File='Get-IisConfigurationSnapshot.ps1';   Name='IIS configuration (if present)' }
    @{ File='Get-PrintServerInventory.ps1';       Name='Print server inventory (if present)' }
    @{ File='Get-MigrationRiskEventLogSummary.ps1'; Name='Risk event log summary' }
)

# Execute collectors
$results = New-Object System.Collections.Generic.List[object]

foreach ($c in $collectors) {
    $path = Join-Path $PSScriptRoot $c.File

    if (-not (Test-Path -LiteralPath $path)) {
        Write-MigrationLog -Level WARN -Message "Collector missing: $($c.File) (skipping)" -LogPath $logPath
        $results.Add([pscustomobject]@{ Collector=$c.File; Status='Missing'; Notes='File not found' })
        continue
    }

    Write-MigrationLog -Level INFO -Message "Running: $($c.Name) [$($c.File)]" -LogPath $logPath

    try {
        & $path -OutputRoot $run.OutputRoot -LogPath $logPath -ServerName $ServerName
        $results.Add([pscustomobject]@{ Collector=$c.File; Status='Success'; Notes=$null })
    }
    catch {
        Write-MigrationLog -Level ERROR -Message "Collector failed: $($c.File) :: $($_.Exception.Message)" -LogPath $logPath
        $results.Add([pscustomobject]@{ Collector=$c.File; Status='Failed'; Notes=$_.Exception.Message })
        continue
    }
}

# Write run results
$results | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $run.OutputRoot '99-CollectorResults.json') -Encoding UTF8

Write-MigrationLog -Level INFO -Message "Preflight complete. Results written to: $($run.OutputRoot)" -LogPath $logPath
