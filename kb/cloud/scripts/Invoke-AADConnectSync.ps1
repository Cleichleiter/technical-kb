# kb\cloud\scripts\Get-AADConnectSchedulerStatus.ps1
<#
.SYNOPSIS
Returns Entra Connect scheduler status and key configuration flags.

.DESCRIPTION
Wraps Get-ADSyncScheduler and highlights the common health indicators:
- SyncCycleEnabled
- StagingModeEnabled
- NextSyncCyclePolicyType
- NextSyncCycleStartTimeInUTC
- CurrentlyEffectiveSyncCycleInterval

WHEN TO USE
- “Sync stopped” complaints
- Verifying staging mode / active server selection
- Confirming the scheduler is enabled and running on the right host

.NOTES
Read-only. Requires ADSync module and should be run on the Entra Connect server.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '_shared\Assert-Module.ps1')

Assert-Module -Name 'ADSync' | Out-Null

$s = Get-ADSyncScheduler -ErrorAction Stop

# Minimal health flags
$issues = New-Object System.Collections.Generic.List[string]
if (-not $s.SyncCycleEnabled) { $issues.Add('SyncCycleEnabled is FALSE (scheduler disabled).') | Out-Null }
if ($s.StagingModeEnabled)    { $issues.Add('StagingModeEnabled is TRUE (this server will not export to Entra ID).') | Out-Null }

[pscustomobject]@{
    Check      = 'AADConnectScheduler'
    Timestamp  = Get-Date
    ComputerName = $env:COMPUTERNAME

    SyncCycleEnabled = $s.SyncCycleEnabled
    StagingModeEnabled = $s.StagingModeEnabled
    NextSyncCyclePolicyType = $s.NextSyncCyclePolicyType
    NextSyncCycleStartTimeInUTC = $s.NextSyncCycleStartTimeInUTC
    CurrentlyEffectiveSyncCycleInterval = $s.CurrentlyEffectiveSyncCycleInterval

    Raw = $s | Select-Object *

    HasIssues    = [bool]($issues.Count -gt 0)
    IssueReasons = $issues
}
