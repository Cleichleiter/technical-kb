# Test-StartupFailures.ps1
<#
.SYNOPSIS
Collects boot/startup failure signals and driver/service initialization issues from event logs.

.DESCRIPTION
Checks high-signal sources:
- System log for:
  - Kernel-Boot / Kernel-General startup warnings/errors
  - Service Control Manager failures (service start timeouts, failures)
  - Driver initialization issues
- Optional: Windows Diagnostics-Performance (boot degradation) if present

WHEN TO USE
- Slow boots
- Systems failing to start services
- Post-driver or update issues
- Unstable servers after reboots

NOTES
Read-only. Safe for production.
#>

[CmdletBinding()]
param(
    [int]$DaysBack = 14,
    [int]$MaxEvents = 400
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-EventLogExists {
    param([Parameter(Mandatory)][string]$LogName)
    try { Get-WinEvent -ListLog $LogName -ErrorAction Stop | Out-Null; $true }
    catch { $false }
}

$start = (Get-Date).AddDays(-1 * $DaysBack)

$items = New-Object System.Collections.Generic.List[object]

# System log providers of interest
if (Test-EventLogExists -LogName 'System') {
    $providers = @(
        'Service Control Manager',
        'Microsoft-Windows-Kernel-Boot',
        'Microsoft-Windows-Kernel-General',
        'Microsoft-Windows-DriverFrameworks-UserMode',
        'Microsoft-Windows-DriverFrameworks-KernelMode',
        'Microsoft-Windows-WER-SystemErrorReporting'
    )

    try {
        $sys = Get-WinEvent -FilterHashtable @{ LogName='System'; StartTime=$start } -ErrorAction Stop |
            Where-Object {
                $_.LevelDisplayName -in @('Error','Warning') -and
                ($providers -contains $_.ProviderName -or $_.ProviderName -match 'Kernel|Driver|Service Control Manager')
            } |
            Sort-Object TimeCreated -Descending |
            Select-Object -First $MaxEvents

        foreach ($e in $sys) {
            $items.Add([pscustomobject]@{
                SourceLog  = 'System'
                TimeCreated= $e.TimeCreated
                Level      = $e.LevelDisplayName
                Id         = $e.Id
                Provider   = $e.ProviderName
                Message    = (($_.Message -replace '\s+',' ').Trim())
            }) | Out-Null
        }
    } catch {
        $items.Add([pscustomobject]@{
            SourceLog='System'; TimeCreated=$null; Level='ERROR'; Id=$null; Provider='Get-WinEvent'
            Message="Failed to query startup-related System events: $($_.Exception.Message)"
        }) | Out-Null
    }
}

# Diagnostics-Performance/Operational (boot degradation)
$diagLog = 'Microsoft-Windows-Diagnostics-Performance/Operational'
if (Test-EventLogExists -LogName $diagLog) {
    try {
        $dp = Get-WinEvent -FilterHashtable @{ LogName=$diagLog; StartTime=$start } -ErrorAction Stop |
            Where-Object { $_.LevelDisplayName -in @('Error','Warning') -and $_.Id -in @(100,101,102,200,201,202) } |
            Sort-Object TimeCreated -Descending |
            Select-Object -First $MaxEvents

        foreach ($e in $dp) {
            $items.Add([pscustomobject]@{
                SourceLog  = $diagLog
                TimeCreated= $e.TimeCreated
                Level      = $e.LevelDisplayName
                Id         = $e.Id
                Provider   = $e.ProviderName
                Message    = (($_.Message -replace '\s+',' ').Trim())
            }) | Out-Null
        }
    } catch {
        $items.Add([pscustomobject]@{
            SourceLog=$diagLog; TimeCreated=$null; Level='ERROR'; Id=$null; Provider='Get-WinEvent'
            Message="Failed to query Diagnostics-Performance events: $($_.Exception.Message)"
        }) | Out-Null
    }
}

$events = $items | Sort-Object TimeCreated -Descending | Select-Object -First $MaxEvents

$issues = New-Object System.Collections.Generic.List[string]
$errWarnCount = @($events | Where-Object { $_.Level -in @('Error','Warning') }).Count
if ($errWarnCount -gt 0) { $issues.Add("Startup/boot-related warning/error events detected (count=$errWarnCount).") | Out-Null }

[pscustomobject]@{
    ComputerName = $env:COMPUTERNAME
    Timestamp    = Get-Date
    DaysBack     = $DaysBack
    EventCount   = @($events).Count
    Events       = $events
    HasStartupIssues = [bool]($issues.Count -gt 0)
    IssueReasons     = $issues
}
