# Get-BackupInventory.ps1
<#
.SYNOPSIS
Builds a lightweight, vendor-agnostic backup inventory snapshot for the local server.

.DESCRIPTION
Collects:
- OS + computer role signal (server/workstation)
- Installed backup-related Windows features (best-effort)
- Windows Server Backup presence (wbadmin)
- VSS provider list
- Local volumes, file systems, free space
- Existing shadow copies (best-effort)

.NOTES
Read-only. Safe for production.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop |
    Select-Object Caption, Version, BuildNumber, OSArchitecture, LastBootUpTime

$cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop |
    Select-Object Manufacturer, Model, Domain, PartOfDomain, TotalPhysicalMemory

$serverFeature = $null
try {
    if (Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue) {
        $serverFeature = Get-WindowsFeature -Name Windows-Server-Backup -ErrorAction SilentlyContinue |
            Select-Object Name, DisplayName, InstallState
    }
} catch { }

$wbadmin = $null
try {
    $wbadmin = Get-Command wbadmin.exe -ErrorAction Stop | Select-Object Source, Version
} catch {
    $wbadmin = [pscustomobject]@{ Note = 'wbadmin.exe not found.' }
}

$vssProviders = @()
try {
    $vssProviders = Get-CimInstance -Namespace root\cimv2 -ClassName Win32_ShadowProvider -ErrorAction Stop |
        Select-Object Name, ID, CLSID, Type
} catch {
    $vssProviders = @([pscustomobject]@{ Error = $_.Exception.Message })
}

$volumes = Get-Volume -ErrorAction SilentlyContinue |
    Select-Object DriveLetter, FileSystemLabel, FileSystemType, HealthStatus, OperationalStatus, Size, SizeRemaining

$shadowCopies = @()
try {
    $shadowCopies = Get-CimInstance Win32_ShadowCopy -ErrorAction Stop |
        Select-Object ID, VolumeName, InstallDate, Description, State
} catch {
    $shadowCopies = @([pscustomobject]@{ Note = 'No shadow copies found or access restricted.' })
}

[pscustomobject]@{
    Check        = 'BackupInventory'
    Timestamp    = Get-Date
    ComputerName = $env:COMPUTERNAME
    OS           = $os
    Computer     = $cs
    WindowsServerBackupFeature = $serverFeature
    Wbadmin      = $wbadmin
    VssProviders = $vssProviders
    Volumes      = $volumes
    ShadowCopies = $shadowCopies
}
