# Test-SystemReboots.ps1
<#
.SYNOPSIS
Collects system reboot/crash signals and unexpected shutdown indicators.

.DESCRIPTION
Checks:
- Uptime / last boot time
- Recent reboot-related events in System log:
  - 6005 (Event Log service started)
  - 6006 (Event Log service stopped)
  - 6008 (Unexpected shutdown)
  - 41   (Kernel-Power unexpected restart)
  - 1001 (BugCheck)
  - 1074 (Planned restart/shutdown)
- Basic bugcheck code extraction (best-effort)

WHEN TO USE
- Random reboots
- Stability investigations
- Post-patch incidents
- Hardware/power instability triage

.NOTES
Read-only. Safe for production.
#>

[CmdletBinding()]
param(
    [int]$DaysBack = 30,
    [int]$MaxEvents = 500
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-EventLogExists {
    param([Parameter(Mandatory)][string]$LogName)
    try { Get-WinEvent -ListLog $LogName -ErrorAction Stop | Out-Null; $true }
    catch { $false }
}

$os = Get-CimInstance Win32_OperatingSystem
$bootTime = $os.LastBootUpTime
$uptime = (Get-Date) - $bootTime

$events = @()
if (Test-EventLogExists -LogName 'System') {
    $start = (Get-Date).AddDays(-1 * $DaysBack)
    $targetIds = @(41, 6008, 1001, 1074, 6005, 6006)

    try {
        $events = Get-WinEvent -FilterHashtable @{ LogName='System'; StartTime=$start } -ErrorAction Stop |
            Where-Object { $_.Id -in $targetIds } |
            Sort-Object TimeCreated -Descending |
            Select-Object -First $MaxEvents |
            ForEach-Object {
                $msg = if ($_.Message) { ($_.Message -replace '\s+',' ').Trim() } else { '' }

                # Best-effort parse bugcheck code from message
                $bugcheck = $null
                if ($_.Id -eq 1001 -and $msg -match '(?i)bugcheckcode\s+(\d+)') {
                    $bugcheck = $matches[1]
                }

                [pscustomobject]@{
                    TimeCreated   = $_.TimeCreated
                    Id            = $_.Id
                    Provider      = $_.ProviderName
                    Level         = $_.LevelDisplayName
                    BugcheckCode  = $bugcheck
                    Message       = $msg
                }
            }
    } catch {
        $events = @(
            [pscustomobject]@{
                TimeCreated  = $null
                Id           = $null
                Provider     = 'Get-WinEvent'
                Level        = 'ERROR'
                BugcheckCode = $null
                Message      = "Failed to query reboot events: $($_.Exception.Message)"
            }
        )
    }
}

$unexpected = @($events | Where-Object { $_.Id -in @(41,6008,1001) })
$planned    = @($events | Where-Object { $_.Id -eq 1074 })

$issues = New-Object System.Collections.Generic.List[string]
if ($unexpected.Count -gt 0) { $issues.Add("Unexpected reboot/shutdown signals detected (count=$($unexpected.Count)).") | Out-Null }

[pscustomobject]@{
    ComputerName = $env:COMPUTERNAME
    Timestamp    = Get-Date

    LastBootTime = $bootTime
    UptimeDays   = [math]::Round($uptime.TotalDays, 2)

    Events = [pscustomobject]@{
        DaysBack      = $DaysBack
        EventCount    = @($events).Count
        Unexpected    = $unexpected
        Planned       = $planned
        All           = $events
    }

    HasRebootIssues = [bool]($issues.Count -gt 0)
    IssueReasons    = $issues
}
