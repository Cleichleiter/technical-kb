# Invoke-NetworkHealthCheck.ps1
<#
.SYNOPSIS
Runs a standardized suite of networking health checks and writes structured artifacts.

.DESCRIPTION
Orchestrates modular networking diagnostics in a consistent order and writes:
- run.log
- per-check JSON outputs
- Summary.json

Designed for outage triage, pre-migration validation, and repeatable evidence capture.

.PARAMETER OutputRoot
Root folder for run artifacts. A run subfolder is created per execution.

.PARAMETER RunName
Optional custom run folder name. Default: <COMPUTER>-<timestamp>.

.PARAMETER Include
Which check group(s) to run.

.PARAMETER Skip
Check names to skip (match the section name used in this script).

.PARAMETER DnsTargets
DNS names to test in Test-DNSResolution.ps1.

.PARAMETER PingTargets
IP/FQDN targets used for latency/loss checks (where applicable).

.NOTES
Read-only. Safe for production.
#>

[CmdletBinding()]
param(
    [string]$OutputRoot = (Join-Path $env:ProgramData 'TechnicalKB\NetworkHealth'),
    [string]$RunName,
    [ValidateSet('All','Core','DNS','Performance','Security','VPN')]
    [string]$Include = 'All',
    [string[]]$Skip = @(),

    [string[]]$DnsTargets = @('microsoft.com','cloudflare.com'),
    [string[]]$PingTargets = @('1.1.1.1','8.8.8.8')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$shared = Join-Path $PSScriptRoot '_shared'
. (Join-Path $shared 'Write-NetworkLog.ps1')

if (-not $RunName) {
    $RunName = "{0}-{1}" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmmss')
}

$runPath = Join-Path $OutputRoot $RunName
New-Item -ItemType Directory -Path $runPath -Force | Out-Null

$logPath = Join-Path $runPath 'run.log'
Write-NetworkLog -Message "Starting Network health check. Include=$Include RunPath=$runPath" -Path $logPath

function Write-SectionJson {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][object]$Object
    )
    $path = Join-Path $runPath ("{0}.json" -f $Name)
    $Object | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Invoke-Section {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Script,
        [hashtable]$Args
    )

    if ($Skip -contains $Name -or $Skip -contains $Script) {
        Write-NetworkLog -Message "Skipping: $Name" -Level WARN -Path $logPath
        return [pscustomobject]@{
            Section   = $Name
            Status    = 'SKIP'
            Timestamp = (Get-Date)
            Output    = $null
        }
    }

    Write-NetworkLog -Message "Running: $Name ($Script)" -Path $logPath

    try {
        $result = & (Join-Path $PSScriptRoot $Script) @Args
        $outFile = Write-SectionJson -Name $Name -Object $result
        return [pscustomobject]@{
            Section   = $Name
            Status    = 'OK'
            Timestamp = (Get-Date)
            Output    = $outFile
        }
    } catch {
        $err = [pscustomobject]@{
            Section   = $Name
            Status    = 'FAIL'
            Timestamp = (Get-Date)
            Error     = $_.Exception.Message
            Detail    = $_.ToString()
        }
        $outFile = Write-SectionJson -Name $Name -Object $err
        Write-NetworkLog -Message "FAILED: $Name. $($_.Exception.Message)" -Level ERROR -Path $logPath
        return [pscustomobject]@{
            Section   = $Name
            Status    = 'FAIL'
            Timestamp = (Get-Date)
            Output    = $outFile
        }
    }
}

$sections = New-Object System.Collections.Generic.List[object]

# Core (configuration first)
if ($Include -in @('All','Core')) {
    $sections.Add((Invoke-Section -Name '01-NetworkConfiguration' -Script 'Get-NetworkConfiguration.ps1' -Args @{})) | Out-Null
    $sections.Add((Invoke-Section -Name '02-AdapterStatus' -Script 'Get-NetworkAdapterStatus.ps1' -Args @{})) | Out-Null
    $sections.Add((Invoke-Section -Name '03-IPAddressing' -Script 'Test-IPAddressing.ps1' -Args @{})) | Out-Null
    $sections.Add((Invoke-Section -Name '04-GatewayReachability' -Script 'Test-GatewayReachability.ps1' -Args @{})) | Out-Null
    $sections.Add((Invoke-Section -Name '05-RoutingTable' -Script 'Test-RoutingTable.ps1' -Args @{})) | Out-Null
}

# DNS
if ($Include -in @('All','DNS')) {
    $sections.Add((Invoke-Section -Name '10-DNSResolution' -Script 'Test-DNSResolution.ps1' -Args @{
        Targets = $DnsTargets
    })) | Out-Null
    $sections.Add((Invoke-Section -Name '11-NameResolutionOrder' -Script 'Test-NameResolutionOrder.ps1' -Args @{})) | Out-Null
}

# Performance
if ($Include -in @('All','Performance')) {
    $sections.Add((Invoke-Section -Name '20-NetworkLatency' -Script 'Test-NetworkLatency.ps1' -Args @{
        Targets = $PingTargets
    })) | Out-Null
    $sections.Add((Invoke-Section -Name '21-PacketLoss' -Script 'Test-PacketLoss.ps1' -Args @{
        Targets = $PingTargets
    })) | Out-Null
    $sections.Add((Invoke-Section -Name '22-MTU' -Script 'Test-MTU.ps1' -Args @{})) | Out-Null
    $sections.Add((Invoke-Section -Name '23-TcpipStatistics' -Script 'Get-TcpipStatistics.ps1' -Args @{})) | Out-Null
}

# Security / firewall
if ($Include -in @('All','Security')) {
    $sections.Add((Invoke-Section -Name '30-FirewallProfiles' -Script 'Get-FirewallProfileStatus.ps1' -Args @{})) | Out-Null
}

# VPN / IPSec
if ($Include -in @('All','VPN')) {
    $sections.Add((Invoke-Section -Name '40-VPNConnectivity' -Script 'Test-VPNConnectivity.ps1' -Args @{})) | Out-Null
    $sections.Add((Invoke-Section -Name '41-IPSecHealth' -Script 'Test-IPSecHealth.ps1' -Args @{})) | Out-Null
}

# Telemetry last
if ($Include -in @('All','Core','DNS','Performance','Security','VPN')) {
    $sections.Add((Invoke-Section -Name '90-NetworkCriticalEvents' -Script 'Get-NetworkCriticalEvents.ps1' -Args @{})) | Out-Null
}

$summary = [pscustomobject]@{
    ComputerName = $env:COMPUTERNAME
    Timestamp    = Get-Date
    Include      = $Include
    OutputPath   = $runPath
    SectionsOk   = @($sections | Where-Object { $_.Status -eq 'OK' }).Count
    SectionsFail = @($sections | Where-Object { $_.Status -eq 'FAIL' }).Count
    SectionsSkip = @($sections | Where-Object { $_.Status -eq 'SKIP' }).Count
    Sections     = $sections
    Log          = $logPath
}

$summaryPath = Write-SectionJson -Name 'Summary' -Object $summary
Write-NetworkLog -Message "Completed Network health check. Summary=$summaryPath" -Path $logPath

$summary
