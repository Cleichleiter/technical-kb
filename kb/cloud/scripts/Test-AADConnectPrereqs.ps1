# kb\cloud\scripts\Test-AADConnectPrereqs.ps1
<#
.SYNOPSIS
Validates whether this host is an Entra Connect (Azure AD Connect) server and checks core prerequisites.

.DESCRIPTION
Checks:
- ADSync service presence and status
- ADSync PowerShell module availability
- Entra Connect scheduler status (if available)
- Current user elevation (optional)

WHEN TO USE
- Before running any sync commands
- When troubleshooting "sync not running" scenarios
- During initial triage on a suspected AAD Connect server

.NOTES
Read-only. Safe for production.
#>

[CmdletBinding()]
param(
    [switch]$RequireAdmin
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '_shared\Write-CloudLog.ps1')
. (Join-Path $PSScriptRoot '_shared\Assert-RunAsAdmin.ps1')

$issues = New-Object System.Collections.Generic.List[string]

if ($RequireAdmin) {
    try { Assert-RunAsAdmin | Out-Null }
    catch { $issues.Add($_.Exception.Message) | Out-Null }
}

$adSyncSvc = Get-Service -Name 'ADSync' -ErrorAction SilentlyContinue
$adSyncSvcStatus = if ($adSyncSvc) { $adSyncSvc.Status.ToString() } else { 'NotFound' }

if (-not $adSyncSvc) {
    $issues.Add('ADSync service not found. This machine may not be an Entra Connect server.') | Out-Null
} elseif ($adSyncSvcStatus -ne 'Running') {
    $issues.Add("ADSync service is not running (Status=$adSyncSvcStatus).") | Out-Null
}

$moduleOk = $false
try {
    $m = Get-Module -ListAvailable -Name 'ADSync' | Sort-Object Version -Descending | Select-Object -First 1
    if ($m) { $moduleOk = $true }
    else { $issues.Add('ADSync PowerShell module not found (module name: ADSync).') | Out-Null }
} catch {
    $issues.Add("Failed to query ADSync module: $($_.Exception.Message)") | Out-Null
}

# Scheduler status (best-effort)
$scheduler = $null
$schedulerError = $null
if ($moduleOk) {
    try {
        Import-Module ADSync -ErrorAction Stop | Out-Null
        $scheduler = Get-ADSyncScheduler -ErrorAction Stop | Select-Object *
    } catch {
        $schedulerError = $_.Exception.Message
        $issues.Add("Failed to read Entra Connect scheduler: $schedulerError") | Out-Null
    }
}

[pscustomobject]@{
    Check       = 'AADConnectPrereqs'
    Timestamp   = Get-Date
    ComputerName= $env:COMPUTERNAME

    ADSyncService = [pscustomobject]@{
        Present = [bool]$adSyncSvc
        Status  = $adSyncSvcStatus
        StartType = if ($adSyncSvc) { (Get-CimInstance Win32_Service -Filter "Name='ADSync'").StartMode } else { $null }
    }

    ADSyncModulePresent = $moduleOk
    Scheduler           = $scheduler
    SchedulerError      = $schedulerError

    HasIssues    = [bool]($issues.Count -gt 0)
    IssueReasons = $issues
}
