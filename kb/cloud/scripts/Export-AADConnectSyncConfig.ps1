# kb\cloud\scripts\Export-AADConnectSyncConfig.ps1
<#
.SYNOPSIS
Exports non-secret Entra Connect sync configuration evidence for troubleshooting.

.DESCRIPTION
Exports:
- ADSync scheduler settings
- ADSync service details
- Installed AAD Connect/ADSync-related programs (best-effort)
- AAD Connect-related event summary (counts)

WHEN TO USE
- You need a quick config snapshot for tickets/escalations
- Auditing what host is running the scheduler and whether staging mode is enabled
- Comparing two AAD Connect servers (active vs staging)

.NOTES
Does not export secrets or connector credentials.
Read-only. Safe for production.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '_shared\Assert-Module.ps1')

$dir = Split-Path -Path $OutPath -Parent
if ($dir -and -not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

$svc = Get-Service -Name 'ADSync' -ErrorAction SilentlyContinue
$svcCim = $null
if ($svc) {
    $svcCim = Get-CimInstance Win32_Service -Filter "Name='ADSync'" -ErrorAction SilentlyContinue |
        Select-Object Name, DisplayName, StartMode, State, PathName
}

$scheduler = $null
$schedulerError = $null
try {
    Assert-Module -Name 'ADSync' | Out-Null
    $scheduler = Get-ADSyncScheduler -ErrorAction Stop | Select-Object *
} catch {
    $schedulerError = $_.Exception.Message
}

# Installed programs (best-effort; avoids Win32_Product)
$uninstallPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

$programs = foreach ($p in $uninstallPaths) {
    Get-ItemProperty -Path $p -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match 'Azure AD Connect|Entra Connect|ADSync|Identity Integration|MIIS' } |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate
}

# Event counts only (fast)
$eventSummary = $null
try {
    $start = (Get-Date).AddDays(-7)
    $eventSummary = Get-WinEvent -FilterHashtable @{ LogName='Application'; StartTime=$start } -ErrorAction Stop |
        Where-Object { $_.LevelDisplayName -in @('Error','Warning') -and $_.ProviderName -match 'ADSync|MIIS|Sync|Azure AD' } |
        Group-Object ProviderName, LevelDisplayName |
        Select-Object @{n='Provider';e={$_.Name.Split(',')[0]}}, @{n='Level';e={$_.Name.Split(',')[1]}}, Count
} catch { }

$export = [pscustomobject]@{
    ComputerName = $env:COMPUTERNAME
    Timestamp    = Get-Date

    ADSyncService = [pscustomobject]@{
        Present = [bool]$svc
        Status  = if ($svc) { $svc.Status.ToString() } else { 'NotFound' }
        Detail  = $svcCim
    }

    Scheduler      = $scheduler
    SchedulerError = $schedulerError

    InstalledPrograms = $programs
    EventSummary       = $eventSummary
}

$export | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutPath -Encoding UTF8
$export
