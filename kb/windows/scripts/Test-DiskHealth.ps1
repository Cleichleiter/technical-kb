# Test-DiskHealth.ps1
<#
.SYNOPSIS
Checks basic disk health signals (SMART/predictive failure, disk errors, offline disks, and NTFS/chkdsk indicators).

.DESCRIPTION
Collects high-signal storage diagnostics:
- Physical disk predictive failure status (best-effort via MSStorageDriver_FailurePredictStatus)
- Disk/partition inventory
- Disk "Status" and "OperationalStatus" where available
- Recent disk-related event signals from System log (Disk, StorAHCI, stornvme, Ntfs, volsnap, partmgr)

WHEN TO USE
- Performance degradation
- Event log shows disk/NTFS errors
- Patch failures or random application crashes
- Prior to migrations or heavy I/O operations

.NOTES
Read-only. Safe for production.
SMART classes vary by hardware/driver; script records availability.
#>

[CmdletBinding()]
param(
    [int]$DaysBack = 7,
    [int]$MaxEvents = 300
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-EventLogExists {
    param([Parameter(Mandatory)][string]$LogName)
    try { Get-WinEvent -ListLog $LogName -ErrorAction Stop | Out-Null; $true }
    catch { $false }
}

function Get-DiskEvents {
    param([datetime]$StartTime, [int]$MaxEvents)

    if (-not (Test-EventLogExists -LogName 'System')) { return @() }

    $providers = @(
        'Disk',
        'Ntfs',
        'volsnap',
        'partmgr',
        'storahci',
        'stornvme',
        'iaStorA',
        'iaStorAC',
        'Microsoft-Windows-Storage-ClassPnP',
        'Microsoft-Windows-Kernel-PnP'
    )

    try {
        Get-WinEvent -FilterHashtable @{ LogName='System'; StartTime=$StartTime } -ErrorAction Stop |
            Where-Object {
                $_.LevelDisplayName -in @('Error','Warning') -and
                ($providers -contains $_.ProviderName)
            } |
            Select-Object -First $MaxEvents |
            ForEach-Object {
                [pscustomobject]@{
                    TimeCreated = $_.TimeCreated
                    Level       = $_.LevelDisplayName
                    Id          = $_.Id
                    Provider    = $_.ProviderName
                    Message     = (($_.Message -replace '\s+',' ').Trim())
                }
            }
    } catch {
        @(
            [pscustomobject]@{
                TimeCreated = $null
                Level       = 'ERROR'
                Id          = $null
                Provider    = 'Get-WinEvent'
                Message     = "Failed to query disk-related events: $($_.Exception.Message)"
            }
        )
    }
}

# Physical disks (CIM)
$diskDrives = Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue | ForEach-Object {
    [pscustomobject]@{
        Index         = $_.Index
        Model         = $_.Model
        SerialNumber  = $_.SerialNumber
        InterfaceType = $_.InterfaceType
        MediaType     = $_.MediaType
        SizeGB        = if ($_.Size) { [math]::Round($_.Size / 1GB, 2) } else { $null }
        Status        = $_.Status
        PNPDeviceID   = $_.PNPDeviceID
    }
}

# Storage module physical disk info (if available)
$storagePhysical = @()
try {
    $storagePhysical = Get-PhysicalDisk -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{
            FriendlyName     = $_.FriendlyName
            SerialNumber     = $_.SerialNumber
            MediaType        = $_.MediaType
            HealthStatus     = $_.HealthStatus
            OperationalStatus= ($_.OperationalStatus -join ', ')
            SizeGB           = [math]::Round($_.Size / 1GB, 2)
            CanPool          = $_.CanPool
        }
    }
} catch {
    $storagePhysical = @(
        [pscustomobject]@{
            Note = "Get-PhysicalDisk not available or failed: $($_.Exception.Message)"
        }
    )
}

# SMART predictive failure (best-effort)
$smart = @()
try {
    $smart = Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction Stop |
        ForEach-Object {
            [pscustomobject]@{
                InstanceName     = $_.InstanceName
                PredictFailure   = [bool]$_.PredictFailure
                Reason           = $_.Reason
            }
        }
} catch {
    $smart = @(
        [pscustomobject]@{
            Note = "SMART predictive status not available: $($_.Exception.Message)"
        }
    )
}

# Volumes quick view
$volumes = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue |
    ForEach-Object {
        $freePct = if ($_.Size -gt 0) { [math]::Round(($_.FreeSpace / $_.Size) * 100, 2) } else { $null }
        [pscustomobject]@{
            Drive       = $_.DeviceID
            VolumeName  = $_.VolumeName
            FileSystem  = $_.FileSystem
            SizeGB      = [math]::Round($_.Size / 1GB, 2)
            FreeGB      = [math]::Round($_.FreeSpace / 1GB, 2)
            FreePercent = $freePct
        }
    }

# Events
$events = Get-DiskEvents -StartTime ((Get-Date).AddDays(-1 * $DaysBack)) -MaxEvents $MaxEvents

# Heuristic issues
$issues = New-Object System.Collections.Generic.List[string]

if (@($diskDrives | Where-Object { $_.Status -and $_.Status -ne 'OK' }).Count -gt 0) {
    $issues.Add('One or more disks report non-OK status in Win32_DiskDrive.') | Out-Null
}

if (@($storagePhysical | Where-Object { $_.HealthStatus -and $_.HealthStatus -ne 'Healthy' }).Count -gt 0) {
    $issues.Add('One or more disks report non-Healthy HealthStatus from Get-PhysicalDisk.') | Out-Null
}

if (@($smart | Where-Object { $_.PredictFailure -eq $true }).Count -gt 0) {
    $issues.Add('SMART predictive failure flagged on one or more disks.') | Out-Null
}

$diskEventCount = @($events | Where-Object { $_.Level -in @('Error','Warning') }).Count
if ($diskEventCount -gt 0) {
    $issues.Add("Disk/NTFS/storage-related warnings/errors detected in System log (count=$diskEventCount).") | Out-Null
}

[pscustomobject]@{
    ComputerName = $env:COMPUTERNAME
    Timestamp    = Get-Date

    Win32DiskDrive   = $diskDrives
    PhysicalDisk     = $storagePhysical
    SmartPredict     = $smart
    Volumes          = $volumes

    Events = [pscustomobject]@{
        DaysBack   = $DaysBack
        EventCount = @($events).Count
        Items      = $events
    }

    HasDiskIssues = [bool]($issues.Count -gt 0)
    IssueReasons  = $issues
}
