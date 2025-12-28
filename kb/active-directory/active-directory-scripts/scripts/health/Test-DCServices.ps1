<#
.SYNOPSIS
Validates core Domain Controller services and key dependencies (status, start type, and basic sanity signals).

.DESCRIPTION
Test-DCServices checks critical DC services (AD DS, Netlogon, KDC, DNS, DFSR, Time, RPC, Event Log, SMB)
and returns a structured report that highlights:
- Services missing vs present
- Not-running services that should be running
- Disabled start types where that is unexpected
- Optional: dependent services and recent service-related event log signals

This is a fast, high-signal script when a DC "feels unhealthy" (auth delays, replication issues, SYSVOL issues).

WHEN TO USE
- During incidents: logon problems, GPO failures, replication errors, SYSVOL/DFSR problems
- After patching or rebooting a DC
- When validating a newly promoted DC

NOTES
- Read-only.
- Some services may be legitimately absent (e.g., DNS service if DC is not hosting DNS).
- This script intentionally avoids changing service state.
#>

[CmdletBinding()]
param(
    # Override or extend the default service list (names, not display names).
    [string[]]$ServiceNames = @(
        'NTDS',          # AD DS (present on DCs)
        'Netlogon',      # DC locator / secure channel / logon
        'KDC',           # Kerberos Key Distribution Center
        'DNS',           # DNS Server role (may not be installed on all DCs)
        'DFSR',          # SYSVOL replication
        'W32Time',       # Windows Time
        'LanmanServer',  # SMB server (SYSVOL/NETLOGON shares)
        'LanmanWorkstation',
        'RpcSs',         # RPC
        'EventLog'       # Windows Event Log
    ),

    # If set, include dependent services for each checked service.
    [switch]$IncludeDependencies,

    # If set, include recent Service Control Manager warning/error events (System log)
    [switch]$IncludeServiceEvents,

    # Days back for Service Control Manager event search (only used with -IncludeServiceEvents)
    [int]$ServiceEventDaysBack = 3,

    # Maximum service-related events to return (only used with -IncludeServiceEvents)
    [int]$MaxServiceEvents = 200
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ServiceStartMode {
    param([Parameter(Mandatory)][string]$Name)
    try {
        (Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction Stop).StartMode
    } catch {
        $null
    }
}

function Get-ServiceDependentList {
    param([Parameter(Mandatory)][System.ServiceProcess.ServiceController]$Service)
    try {
        $Service.DependentServices | Select-Object -ExpandProperty Name
    } catch {
        @()
    }
}

function Get-ServiceRequiredByList {
    param([Parameter(Mandatory)][System.ServiceProcess.ServiceController]$Service)
    try {
        $Service.ServicesDependedOn | Select-Object -ExpandProperty Name
    } catch {
        @()
    }
}

# These are "expected to be running" for a healthy DC in most environments.
# DNS may be absent or stopped if the DC is not hosting DNS.
$expectedRunning = @(
    'NTDS',
    'Netlogon',
    'KDC',
    'DFSR',
    'W32Time',
    'LanmanServer',
    'RpcSs',
    'EventLog'
)

$computer = $env:COMPUTERNAME
$now = Get-Date

$serviceResults = foreach ($name in $ServiceNames) {
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue

    if (-not $svc) {
        [pscustomobject]@{
            ComputerName        = $computer
            Name                = $name
            DisplayName         = $null
            Present             = $false
            Status              = 'NotFound'
            StartType           = $null
            ExpectedToBeRunning = $expectedRunning -contains $name
            IsProblem           = $expectedRunning -contains $name
            ProblemReason       = if ($expectedRunning -contains $name) { 'Missing service' } else { $null }
            DependsOn           = if ($IncludeDependencies) { @() } else { $null }
            DependentServices   = if ($IncludeDependencies) { @() } else { $null }
        }
        continue
    }

    $startMode = Get-ServiceStartMode -Name $svc.Name
    $statusStr = $svc.Status.ToString()

    $expRun = $expectedRunning -contains $svc.Name

    $problem = $false
    $reason = @()

    if ($expRun -and $svc.Status -ne 'Running') {
        $problem = $true
        $reason += "Expected Running but is $statusStr"
    }

    if ($expRun -and $startMode -eq 'Disabled') {
        $problem = $true
        $reason += "StartType is Disabled"
    }

    # DNS: if installed, commonly expected to run on DCs that host DNS.
    # If it exists and is stopped/disabled, flag but with a softer reason.
    if ($svc.Name -eq 'DNS' -and $svc.Status -ne 'Running') {
        $reason += "DNS service present but not running (verify if this DC hosts DNS)"
        $problem = $true
    }
    if ($svc.Name -eq 'DNS' -and $startMode -eq 'Disabled') {
        $reason += "DNS service start type is Disabled (verify intended configuration)"
        $problem = $true
    }

    [pscustomobject]@{
        ComputerName        = $computer
        Name                = $svc.Name
        DisplayName         = $svc.DisplayName
        Present             = $true
        Status              = $statusStr
        StartType           = $startMode
        ExpectedToBeRunning = $expRun
        IsProblem           = $problem
        ProblemReason       = if ($reason.Count -gt 0) { $reason -join '; ' } else { $null }
        DependsOn           = if ($IncludeDependencies) { (Get-ServiceRequiredByList -Service $svc) } else { $null }
        DependentServices   = if ($IncludeDependencies) { (Get-ServiceDependentList -Service $svc) } else { $null }
    }
}

# Optional: recent service-related events
$svcEvents = @()
if ($IncludeServiceEvents) {
    $start = $now.AddDays(-1 * $ServiceEventDaysBack)

    try {
        $svcEvents = Get-WinEvent -FilterHashtable @{
            LogName   = 'System'
            StartTime = $start
        } -ErrorAction Stop |
        Where-Object {
            # Service Control Manager is the most common provider for service failures.
            $_.ProviderName -in @('Service Control Manager','Microsoft-Windows-ServiceControlManager') -and
            $_.LevelDisplayName -in @('Error','Warning')
        } |
        Select-Object -First $MaxServiceEvents |
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
        $svcEvents = @(
            [pscustomobject]@{
                TimeCreated = $null
                Level       = 'ERROR'
                Id          = $null
                Provider    = 'Get-WinEvent'
                Message     = "Failed to query System log for service events: $($_.Exception.Message)"
            }
        )
    }
}

# Summary flags
$problems = $serviceResults | Where-Object { $_.IsProblem }

[pscustomobject]@{
    ComputerName   = $computer
    Timestamp      = $now
    ProblemCount   = $problems.Count
    Problems       = $problems
    Services       = $serviceResults
    ServiceEvents  = if ($IncludeServiceEvents) { $svcEvents } else { $null }
}
