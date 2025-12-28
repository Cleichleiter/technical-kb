<#
.SYNOPSIS
Triggers an Entra Connect (Azure AD Connect) Delta sync cycle.

.DESCRIPTION
Runs Start-ADSyncSyncCycle -PolicyType Delta and returns scheduler status afterward.

WHEN TO USE
- After on-prem AD user/group changes that need to reach Entra ID quickly
- After resolving sync errors and validating exports resume
- Routine “force a delta” troubleshooting

NOTES
- Must be run on the Entra Connect server.
- Requires ADSync module.
- This script does not modify configuration; it only triggers a sync run.
#>

[CmdletBinding()]
param(
    [switch]$RequireAdmin
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Shared helpers (optional; remove if you don't want dependencies)
$shared = Join-Path $PSScriptRoot '_shared'
$logHelper = Join-Path $shared 'Write-CloudLog.ps1'
$adminHelper = Join-Path $shared 'Assert-RunAsAdmin.ps1'
$moduleHelper = Join-Path $shared 'Assert-Module.ps1'

if (Test-Path -LiteralPath $logHelper)   { . $logHelper }
if (Test-Path -LiteralPath $adminHelper) { . $adminHelper }
if (Test-Path -LiteralPath $moduleHelper){ . $moduleHelper }

if ($RequireAdmin -and (Get-Command Assert-RunAsAdmin -ErrorAction SilentlyContinue)) {
    Assert-RunAsAdmin | Out-Null
}

# Ensure ADSync module is available
if (Get-Command Assert-Module -ErrorAction SilentlyContinue) {
    Assert-Module -Name 'ADSync' | Out-Null
} else {
    Import-Module ADSync -ErrorAction Stop | Out-Null
}

# Confirm ADSync service
$svc = Get-Service -Name 'ADSync' -ErrorAction Stop
if ($svc.Status -ne 'Running') {
    throw "ADSync service is not running (Status=$($svc.Status)). Start the service before triggering sync."
}

if (Get-Command Write-CloudLog -ErrorAction SilentlyContinue) {
    Write-CloudLog -Message 'Triggering Entra Connect delta sync (PolicyType=Delta).' -Level INFO
}

$result = Start-ADSyncSyncCycle -PolicyType Delta -ErrorAction Stop

# Scheduler status (evidence)
$scheduler = $null
try { $scheduler = Get-ADSyncScheduler -ErrorAction Stop | Select-Object * } catch { }

[pscustomobject]@{
    Check        = 'AADConnectDeltaSync'
    Timestamp    = Get-Date
    ComputerName = $env:COMPUTERNAME
    PolicyType   = 'Delta'
    StartResult  = $result
    Scheduler    = $scheduler
}
