# kb\cloud\scripts\Get-AADConnectSyncErrors.ps1
<#
.SYNOPSIS
Collects high-signal Entra Connect (AAD Connect) sync errors from event logs.

.DESCRIPTION
Queries:
- Application log providers commonly used by AAD Connect components
- Directory Synchronization / AADConnect operational logs when present (varies by version)

Filters for Warning/Error and returns normalized output.

WHEN TO USE
- Users/groups not syncing to Entra ID
- Suspected connector failures
- You need evidence for escalation (Microsoft / vendor)

.NOTES
Read-only. Safe for production.
Event providers vary by version; script records what it can find.
#>

[CmdletBinding()]
param(
    [int]$DaysBack = 7,
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

$targets = @(
    # Often seen in AAD Connect environments; exact names vary
    'Application',
    'System',
    'Microsoft-Windows-AAD/Operational',
    'Microsoft-Windows-User Device Registration/Operational'
)

# Application providers that frequently carry AAD Connect/MIIS signals
$appProviders = @(
    'Directory Synchronization',
    'ADSync',
    'Microsoft Azure AD Sync',
    'MIIS Server',
    'Microsoft-IdentityIntegrationServer',
    'AD FS',
    'Microsoft-Windows-AAD'
)

$items = New-Object System.Collections.Generic.List[object]

foreach ($log in $targets) {
    if (-not (Test-EventLogExists -LogName $log)) { continue }

    try {
        $ev = Get-WinEvent -FilterHashtable @{ LogName=$log; StartTime=$start } -ErrorAction Stop |
            Where-Object {
                $_.LevelDisplayName -in @('Error','Warning') -and (
                    ($log -eq 'Application' -and ($appProviders -contains $_.ProviderName -or $_.ProviderName -match 'ADSync|MIIS|Sync|Azure AD')) -or
                    ($log -ne 'Application')
                )
            } |
            Sort-Object TimeCreated -Descending |
            Select-Object -First $MaxEvents

        foreach ($e in $ev) {
            $items.Add([pscustomobject]@{
                LogName     = $log
                TimeCreated = $e.TimeCreated
                Level       = $e.LevelDisplayName
                Id          = $e.Id
                Provider    = $e.ProviderName
                Message     = (($_.Message -replace '\s+',' ').Trim())
            }) | Out-Null
        }
    } catch {
        $items.Add([pscustomobject]@{
            LogName     = $log
            TimeCreated = $null
            Level       = 'ERROR'
            Id          = $null
            Provider    = 'Get-WinEvent'
            Message     = "Failed to query log $log: $($_.Exception.Message)"
        }) | Out-Null
    }
}

$events = $items | Sort-Object TimeCreated -Descending | Select-Object -First $MaxEvents

$issues = New-Object System.Collections.Generic.List[string]
if (@($events | Where-Object { $_.Level -in @('Error','Warning') }).Count -gt 0) {
    $issues.Add('AAD Connect-related warnings/errors detected in event logs.') | Out-Null
}

[pscustomobject]@{
    Check        = 'AADConnectSyncErrors'
    Timestamp    = Get-Date
    ComputerName = $env:COMPUTERNAME
    DaysBack     = $DaysBack
    EventCount   = @($events).Count
    Events       = $events
    HasIssues    = [bool]($issues.Count -gt 0)
    IssueReasons = $issues
}
