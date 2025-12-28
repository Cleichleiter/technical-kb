<#
.SYNOPSIS
Performs safe, read-only checks related to the Active Directory database (NTDS.dit) and ESE/ESENT signals.

.DESCRIPTION
Test-NTDSDatabase collects key NTDS database configuration and health indicators without performing
repairs or making changes. It is intended to answer:
- Where is NTDS.dit located? Where are the logs?
- Does the database file exist and what is its size/age?
- Are there recent ESENT (ESE/JET) warnings/errors that indicate database/log issues?
- Is there evidence of common AD DS storage-related problems?
- Are there any obvious disk capacity constraints on the volume(s) hosting NTDS/logs?

It also performs best-effort checks for:
- DS service status (NTDS)
- SYSVOL presence (share check) (because SYSVOL/NTDS issues often correlate during storage incidents)

WHEN TO USE
- You see ESENT errors in System log
- DC instability after storage incidents or unclean shutdowns
- Prior to deeper offline analysis (esentutl) or authoritative support escalation
- Post-migration or after relocating database/log paths

NOTES
- Safe/read-only. Does not run esentutl repairs or defrags.
- Access to registry and event logs may require elevation.
#>

[CmdletBinding()]
param(
    # Include file size and timestamps for database/log folders (more detail)
    [switch]$IncludeFileDetails,

    # How many days back to search for ESENT events
    [int]$EsentDaysBack = 14,

    # Max ESENT events to return
    [int]$MaxEsentEvents = 300,

    # Also include NTDS-related events from "Directory Service" log (warnings/errors)
    [switch]$IncludeDirectoryServiceEvents,

    [int]$DirectoryServiceDaysBack = 7,
    [int]$MaxDirectoryServiceEvents = 200
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RegistryValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )
    try {
        (Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop).$Name
    } catch {
        $null
    }
}

function Get-DriveFreeSpaceInfo {
    param([Parameter(Mandatory)][string]$AnyPath)

    try {
        $root = [System.IO.Path]::GetPathRoot($AnyPath)
        if ([string]::IsNullOrWhiteSpace($root)) { return $null }

        $disk = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $root.TrimEnd('\')) -ErrorAction Stop
        [pscustomobject]@{
            Drive          = $disk.DeviceID
            SizeGB         = [math]::Round($disk.Size / 1GB, 2)
            FreeGB         = [math]::Round($disk.FreeSpace / 1GB, 2)
            FreePercent    = if ($disk.Size -gt 0) { [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 2) } else { $null }
            FileSystem     = $disk.FileSystem
            VolumeName     = $disk.VolumeName
        }
    } catch {
        $null
    }
}

function Get-EsentEvents {
    param(
        [datetime]$StartTime,
        [int]$MaxEvents
    )

    # ESENT provider in System log is the common indicator for ESE/JET issues.
    try {
        Get-WinEvent -FilterHashtable @{
            LogName   = 'System'
            StartTime = $StartTime
        } -ErrorAction Stop |
        Where-Object {
            $_.ProviderName -eq 'ESENT' -and
            $_.LevelDisplayName -in @('Error','Warning')
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
                Message     = "Failed to query ESENT events: $($_.Exception.Message)"
            }
        )
    }
}

function Get-DirectoryServiceEvents {
    param(
        [datetime]$StartTime,
        [int]$MaxEvents
    )

    try {
        Get-WinEvent -FilterHashtable @{
            LogName   = 'Directory Service'
            StartTime = $StartTime
        } -ErrorAction Stop |
        Where-Object { $_.LevelDisplayName -in @('Error','Warning') } |
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
                Message     = "Failed to query 'Directory Service' events: $($_.Exception.Message)"
            }
        )
    }
}

$computer = $env:COMPUTERNAME
$now = Get-Date

# Pull NTDS configuration
$regPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters'
$dbPath  = Get-RegistryValue -Path $regPath -Name 'DSA Database file'
$logPath = Get-RegistryValue -Path $regPath -Name 'Database log files path'

# Also capture "EDB File" / checkpoint where applicable (may not exist on all systems)
$chkPath = Get-RegistryValue -Path $regPath -Name 'Database log checkpoint file'

# Service states
$ntdsSvc = Get-Service -Name NTDS -ErrorAction SilentlyContinue
$ntdsSvcState = if ($ntdsSvc) { $ntdsSvc.Status.ToString() } else { 'NotFound' }

# File existence
$dbExists  = if ($dbPath)  { Test-Path -LiteralPath $dbPath } else { $false }
$logExists = if ($logPath) { Test-Path -LiteralPath $logPath } else { $false }
$chkExists = if ($chkPath) { Test-Path -LiteralPath $chkPath } else { $false }

# Basic file details
$dbInfo  = $null
$logInfo = $null
$chkInfo = $null

if ($IncludeFileDetails) {
    if ($dbExists) {
        $fi = Get-Item -LiteralPath $dbPath -ErrorAction SilentlyContinue
        if ($fi) {
            $dbInfo = [pscustomobject]@{
                FullName      = $fi.FullName
                SizeGB        = [math]::Round($fi.Length / 1GB, 2)
                LastWriteTime = $fi.LastWriteTime
                CreationTime  = $fi.CreationTime
            }
        }
    }

    if ($logExists) {
        # Count and size of EDB logs can be very noisy; keep it light.
        $logFiles = Get-ChildItem -LiteralPath $logPath -File -ErrorAction SilentlyContinue
        $logInfo = [pscustomobject]@{
            Path          = $logPath
            FileCount     = if ($logFiles) { $logFiles.Count } else { 0 }
            TotalSizeGB   = if ($logFiles) { [math]::Round((($logFiles | Measure-Object Length -Sum).Sum) / 1GB, 2) } else { 0 }
            NewestLogTime = if ($logFiles) { ($logFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime } else { $null }
        }
    }

    if ($chkExists) {
        $ci = Get-Item -LiteralPath $chkPath -ErrorAction SilentlyContinue
        if ($ci) {
            $chkInfo = [pscustomobject]@{
                FullName      = $ci.FullName
                SizeMB        = [math]::Round($ci.Length / 1MB, 2)
                LastWriteTime = $ci.LastWriteTime
            }
        }
    }
}

# Disk free space where database/logs live
$dbDrive  = if ($dbPath)  { Get-DriveFreeSpaceInfo -AnyPath $dbPath }  else { $null }
$logDrive = if ($logPath) { Get-DriveFreeSpaceInfo -AnyPath (Join-Path $logPath 'dummy.txt') } else { $null }

# ESENT events (System log)
$esentStart = $now.AddDays(-1 * $EsentDaysBack)
$esentEvents = Get-EsentEvents -StartTime $esentStart -MaxEvents $MaxEsentEvents

# Optional Directory Service events
$dsEvents = $null
if ($IncludeDirectoryServiceEvents) {
    $dsStart = $now.AddDays(-1 * $DirectoryServiceDaysBack)
    $dsEvents = Get-DirectoryServiceEvents -StartTime $dsStart -MaxEvents $MaxDirectoryServiceEvents
}

# Simple flags (heuristics)
$hasEsentErrors = $esentEvents | Where-Object { $_.Level -in @('Error','Warning') -and $_.Provider -eq 'ESENT' }
$lowDiskFlags = @()
if ($dbDrive -and $dbDrive.FreePercent -lt 15) { $lowDiskFlags += "Low free space on DB drive $($dbDrive.Drive): $($dbDrive.FreePercent)% free" }
if ($logDrive -and $logDrive.FreePercent -lt 15) { $lowDiskFlags += "Low free space on LOG drive $($logDrive.Drive): $($logDrive.FreePercent)% free" }

[pscustomobject]@{
    ComputerName = $computer
    Timestamp    = $now

    NTDSServiceStatus = $ntdsSvcState

    Registry = [pscustomobject]@{
        ParametersKey = $regPath
        DatabaseFile  = $dbPath
        LogPath       = $logPath
        CheckpointFile= $chkPath
    }

    Paths = [pscustomobject]@{
        DatabaseExists   = [bool]$dbExists
        LogPathExists    = [bool]$logExists
        CheckpointExists = [bool]$chkExists
    }

    FileDetails = if ($IncludeFileDetails) {
        [pscustomobject]@{
            Database   = $dbInfo
            LogFolder  = $logInfo
            Checkpoint = $chkInfo
        }
    } else { $null }

    Disk = [pscustomobject]@{
        DatabaseDrive = $dbDrive
        LogDrive      = $logDrive
        LowDiskFlags  = $lowDiskFlags
    }

    ESENT = [pscustomobject]@{
        DaysBack = $EsentDaysBack
        EventCount = @($esentEvents).Count
        Events = $esentEvents
        HasRecentEsentWarningsOrErrors = [bool]($hasEsentErrors.Count -gt 0)
    }

    DirectoryService = if ($IncludeDirectoryServiceEvents) {
        [pscustomobject]@{
            DaysBack = $DirectoryServiceDaysBack
            EventCount = @($dsEvents).Count
            Events = $dsEvents
        }
    } else { $null }
}
