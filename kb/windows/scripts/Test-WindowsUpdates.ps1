# Test-WindowsUpdates.ps1
<#
.SYNOPSIS
Validates Windows Update health signals (services, recent update history signals, and reboot requirements).

.DESCRIPTION
Checks:
- Key update-related services (wuauserv, UsoSvc, bits, TrustedInstaller, CryptSvc)
- Pending reboot indicators (CBS, WU, pending file rename operations)
- Recent WindowsUpdateClient operational warnings/errors (if log exists)
- Basic last-install dates (best-effort via Win32_QuickFixEngineering)

WHEN TO USE
- Patch compliance checks
- Patch failures or endless "Installing updates"
- Post-patch incidents
- Systems that refuse to reboot or report pending reboot state indefinitely

NOTES
Read-only.
Update history sources vary across Windows versions; this script uses best-effort sources and records gaps.
#>

[CmdletBinding()]
param(
    [int]$DaysBack = 30,
    [int]$MaxWUEvents = 300
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ServiceStartMode {
    param([Parameter(Mandatory)][string]$Name)
    try { (Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction Stop).StartMode }
    catch { $null }
}

function Get-PendingRebootSignals {
    $signals = New-Object System.Collections.Generic.List[string]

    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
        $signals.Add('CBS: RebootPending') | Out-Null
    }

    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        $signals.Add('WindowsUpdate: RebootRequired') | Out-Null
    }

    try {
        $p = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction Stop
        if ($p.PendingFileRenameOperations) {
            $signals.Add('SessionManager: PendingFileRenameOperations') | Out-Null
        }
    } catch { }

    $signals
}

function Test-EventLogExists {
    param([Parameter(Mandatory)][string]$LogName)
    try { Get-WinEvent -ListLog $LogName -ErrorAction Stop | Out-Null; $true }
    catch { $false }
}

# Service checks
$serviceNames = @('wuauserv','UsoSvc','bits','TrustedInstaller','CryptSvc')
$services = foreach ($s in $serviceNames) {
    $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
    if (-not $svc) {
        [pscustomobject]@{
            Name      = $s
            Present   = $false
            Status    = 'NotFound'
            StartType = $null
        }
        continue
    }

    [pscustomobject]@{
        Name      = $svc.Name
        Present   = $true
        Status    = $svc.Status.ToString()
        StartType = (Get-ServiceStartMode -Name $svc.Name)
    }
}

# Pending reboot
$pending = Get-PendingRebootSignals

# Windows Update operational events
$wuLog = 'Microsoft-Windows-WindowsUpdateClient/Operational'
$wuEvents = @()
if (Test-EventLogExists -LogName $wuLog) {
    $start = (Get-Date).AddDays(-1 * $DaysBack)
    try {
        $wuEvents = Get-WinEvent -FilterHashtable @{ LogName=$wuLog; StartTime=$start } -ErrorAction Stop |
            Where-Object { $_.LevelDisplayName -in @('Error','Warning') } |
            Select-Object -First $MaxWUEvents |
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
        $wuEvents = @(
            [pscustomobject]@{
                TimeCreated = $null
                Level       = 'ERROR'
                Id          = $null
                Provider    = 'Get-WinEvent'
                Message     = "Failed to query Windows Update operational log: $($_.Exception.Message)"
            }
        )
    }
}

# Hotfix baseline (best-effort)
$hotfix = @()
try {
    $hotfix = Get-CimInstance Win32_QuickFixEngineering -ErrorAction Stop |
        Sort-Object InstalledOn -Descending |
        Select-Object -First 50 |
        Select-Object HotFixID, InstalledOn, Description
} catch {
    $hotfix = @(
        [pscustomobject]@{
            HotFixID     = $null
            InstalledOn  = $null
            Description  = "Failed to query Win32_QuickFixEngineering: $($_.Exception.Message)"
        }
    )
}

# Heuristic issues
$issues = New-Object System.Collections.Generic.List[string]
$svcProblems = $services | Where-Object { -not $_.Present -or $_.StartType -eq 'Disabled' }

if (@($svcProblems).Count -gt 0) {
    $issues.Add('One or more update-related services are missing or disabled.') | Out-Null
}

if ($pending.Count -gt 0) {
    $issues.Add('Pending reboot signals detected.') | Out-Null
}

if (@($wuEvents | Where-Object { $_.Level -in @('Error','Warning') }).Count -gt 0) {
    $issues.Add('Windows Update warnings/errors detected in Operational log.') | Out-Null
}

[pscustomobject]@{
    ComputerName = $env:COMPUTERNAME
    Timestamp    = Get-Date

    Services = $services
    PendingReboot = [pscustomobject]@{
        IsPending = [bool]($pending.Count -gt 0)
        Signals   = $pending
    }

    WindowsUpdateOperational = if (Test-EventLogExists -LogName $wuLog) {
        [pscustomobject]@{
            LogName     = $wuLog
            DaysBack    = $DaysBack
            EventCount  = @($wuEvents).Count
            Events      = $wuEvents
        }
    } else {
        [pscustomobject]@{
            LogName     = $wuLog
            DaysBack    = $DaysBack
            EventCount  = 0
            Events      = @()
            Note        = 'Log not present on this system.'
        }
    }

    Hotfixes = $hotfix

    HasUpdateIssues = [bool]($issues.Count -gt 0)
    IssueReasons    = $issues
}
