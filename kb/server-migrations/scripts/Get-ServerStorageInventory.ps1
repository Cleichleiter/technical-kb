<#
.SYNOPSIS
Collects disk/partition/volume inventory for migration sizing and layout validation.
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

Write-LogLine INFO "Collecting storage inventory..."

$volumes = @()
$disks   = @()
$parts   = @()

try { $disks = Get-Disk | Select-Object Number, FriendlyName, SerialNumber, BusType, PartitionStyle, HealthStatus, OperationalStatus, Size } catch { }
try { $parts = Get-Partition | Select-Object DiskNumber, PartitionNumber, DriveLetter, IsBoot, IsSystem, Size, Type, GptType } catch { }
try {
    $volumes = Get-Volume | Select-Object DriveLetter, FileSystemLabel, FileSystem, AllocationUnitSize, HealthStatus, Size, SizeRemaining, Path
} catch { }

$volCsv = Join-Path $OutputRoot '02-Volumes.csv'
$diskCsv = Join-Path $OutputRoot '02-Disks.csv'
$partCsv = Join-Path $OutputRoot '02-Partitions.csv'

if ($disks)   { $disks  | Export-Csv -LiteralPath $diskCsv -NoTypeInformation }
if ($parts)   { $parts  | Export-Csv -LiteralPath $partCsv -NoTypeInformation }
if ($volumes) { $volumes | Export-Csv -LiteralPath $volCsv -NoTypeInformation }

# Summary JSON
$summary = [pscustomobject]@{
    ServerName = $ServerName
    DiskCount  = @($disks).Count
    VolumeCount = @($volumes).Count
    TotalSizeGB = if ($volumes) { [math]::Round((($volumes | Measure-Object -Property Size -Sum).Sum / 1GB),2) } else { $null }
    TotalFreeGB = if ($volumes) { [math]::Round((($volumes | Measure-Object -Property SizeRemaining -Sum).Sum / 1GB),2) } else { $null }
}
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputRoot '02-StorageSummary.json') -Encoding UTF8

Write-LogLine INFO "Storage inventory complete."
