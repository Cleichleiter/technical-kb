<#
.SYNOPSIS
Validates prerequisites and gathers baseline environment facts before running DC/AD health checks.

.DESCRIPTION
Test-DCPrereqs is intended to run first in a health-check bundle. It verifies:
- The host appears to be a Domain Controller (DomainRole 4/5)
- You are running elevated (Admin) when required
- Required diagnostic binaries exist (dcdiag, repadmin, nltest, w32tm, dfsrmig)
- Key Windows roles/services expected on a DC are present
- Basic identity context (domain, forest, site when possible)
- Network basics (DNS client configuration, key ports listening)

It returns a structured object suitable for logging, JSON export, and later comparisons.

WHEN TO USE
- Before running the rest of the DC health-check suite.
- When troubleshooting why other diagnostics are failing (missing tools, wrong host, permissions).
- During onboarding / documentation of a new domain controller.

NOTES
- Read-only. Does not change system state.
- Some data requires the ActiveDirectory module; the script will degrade gracefully if missing.
#>

[CmdletBinding()]
param(
    # If set, do not throw when not elevated; instead, record Elevated=$false and continue.
    [switch]$AllowNonAdmin,

    # Optional: additional required command names to check
    [string[]]$AdditionalCommands
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p  = New-Object Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Test-CommandExists {
    param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Safe-GetCim {
    param(
        [Parameter(Mandatory)][string]$ClassName
    )
    try { Get-CimInstance -ClassName $ClassName -ErrorAction Stop }
    catch { $null }
}

function Try-ImportADModule {
    try {
        if (-not (Get-Module -Name ActiveDirectory)) {
            Import-Module ActiveDirectory -ErrorAction Stop
        }
        return $true
    } catch {
        return $false
    }
}

function Get-ListeningPorts {
    # Returns a small list of expected DC ports that are actively listening on this host.
    # Note: This checks local listeners, not firewall reachability from clients.
    $expected = @(
        53,    # DNS
        88,    # Kerberos
        135,   # RPC endpoint mapper
        389,   # LDAP
        445,   # SMB
        464,   # Kerberos password change
        636,   # LDAPS (if configured)
        3268,  # Global Catalog
        3269   # Global Catalog over SSL (if configured)
    )

    $listeners = @()
    try {
        $tcp = Get-NetTCPConnection -State Listen -ErrorAction Stop
        foreach ($p in $expected) {
            $isListening = [bool]($tcp | Where-Object { $_.LocalPort -eq $p } | Select-Object -First 1)
            $listeners += [pscustomobject]@{
                Port        = $p
                IsListening = $isListening
            }
        }
    } catch {
        # Fallback for older builds / limited environments
        foreach ($p in $expected) {
            $listeners += [pscustomobject]@{
                Port        = $p
                IsListening = $null
            }
        }
    }

    $listeners
}

# --- Baseline machine facts ---
$cs  = Safe-GetCim -ClassName Win32_ComputerSystem
$os  = Safe-GetCim -ClassName Win32_OperatingSystem
$bios= Safe-GetCim -ClassName Win32_BIOS

$domainRole = if ($cs) { [int]$cs.DomainRole } else { $null }
# 4 = Backup Domain Controller, 5 = Primary Domain Controller
$isDC = $domainRole -in 4,5

$elevated = Test-IsAdmin
if (-not $elevated -and -not $AllowNonAdmin) {
    throw "This prerequisite check requires an elevated PowerShell session (Run as Administrator). Use -AllowNonAdmin to record status without throwing."
}

# --- Command checks ---
$requiredCommands = @('dcdiag.exe','repadmin.exe','nltest.exe','w32tm.exe','dfsrmig.exe')
if ($AdditionalCommands) { $requiredCommands += $AdditionalCommands }

$commandStatus = foreach ($c in $requiredCommands) {
    [pscustomobject]@{
        Name   = $c
        Exists = (Test-CommandExists -Name $c)
        Path   = (Get-Command $c -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue)
    }
}
$missingCommands = $commandStatus | Where-Object { -not $_.Exists } | Select-Object -ExpandProperty Name

# --- Service checks (presence/status) ---
$serviceNames = @(
    'NTDS',        # AD DS
    'Netlogon',
    'KDC',
    'DNS',         # if DNS role installed
    'DFSR',        # SYSVOL replication
    'W32Time',
    'LanmanServer',
    'EventLog',
    'RpcSs'
)

$serviceStatus = foreach ($s in $serviceNames) {
    $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
    if ($svc) {
        [pscustomobject]@{
            Name        = $svc.Name
            DisplayName = $svc.DisplayName
            Status      = $svc.Status.ToString()
            StartType   = (Get-CimInstance Win32_Service -Filter "Name='$($svc.Name)'" -ErrorAction SilentlyContinue).StartMode
        }
    } else {
        [pscustomobject]@{
            Name        = $s
            DisplayName = $null
            Status      = 'NotFound'
            StartType   = $null
        }
    }
}

# --- DNS client config (what this DC points to) ---
$dnsClient = @()
try {
    $dnsClient = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction Stop |
        Select-Object InterfaceAlias, ServerAddresses
} catch {
    # leave empty; not fatal
}

# --- AD context (best-effort) ---
$adModuleLoaded = Try-ImportADModule

$adContext = [pscustomobject]@{
    ADModuleAvailable = [bool]$adModuleLoaded
    DomainDnsRoot     = $null
    Forest            = $null
    Site              = $null
    IsGlobalCatalog   = $null
    IsReadOnly        = $null
}

if ($adModuleLoaded) {
    try {
        $domainObj = Get-ADDomain -ErrorAction Stop
        $forestObj = Get-ADForest -ErrorAction Stop
        $dcObj     = Get-ADDomainController -Identity $env:COMPUTERNAME -ErrorAction Stop

        $adContext.DomainDnsRoot   = $domainObj.DnsRoot
        $adContext.Forest          = $forestObj.Name
        $adContext.Site            = $dcObj.Site
        $adContext.IsGlobalCatalog = $dcObj.IsGlobalCatalog
        $adContext.IsReadOnly      = $dcObj.IsReadOnly
    } catch {
        # best-effort only
    }
}

# --- Listening ports (local) ---
$ports = Get-ListeningPorts

# --- Final result ---
[pscustomobject]@{
    ComputerName = $env:COMPUTERNAME
    Timestamp    = Get-Date

    Elevated     = [bool]$elevated
    DomainRole   = $domainRole
    IsDomainController = [bool]$isDC

    Machine      = [pscustomobject]@{
        Domain        = $cs.Domain
        Manufacturer = $cs.Manufacturer
        Model        = $cs.Model
        OS           = if ($os) { $os.Caption } else { $null }
        OSVersion    = if ($os) { $os.Version } else { $null }
        BuildNumber  = if ($os) { $os.BuildNumber } else { $null }
        InstallDate  = if ($os) { $os.InstallDate } else { $null }
        BIOSVersion  = if ($bios) { ($bios.SMBIOSBIOSVersion) } else { $null }
        LastBootUp   = if ($os) { $os.LastBootUpTime } else { $null }
    }

    ADContext    = $adContext

    Commands     = $commandStatus
    MissingCommands = $missingCommands

    Services     = $serviceStatus

    DnsClientServers = $dnsClient

    ListeningPorts = $ports
}
