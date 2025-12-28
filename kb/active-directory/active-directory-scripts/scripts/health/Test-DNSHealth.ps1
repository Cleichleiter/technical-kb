<#
.SYNOPSIS
Validates DNS health for Active Directory by checking service state, client DNS settings,
and required AD DNS records (SRV/NS/SOA), plus basic name resolution tests.

.DESCRIPTION
Test-DNSHealth is a focused diagnostic for the most common root cause of AD instability: DNS.

It performs:
- DNS Server service status (if installed)
- Local DNS client server configuration (what this DC points to)
- Resolution tests for key AD records:
  - _ldap._tcp.dc._msdcs.<domain> (DC locator)
  - _kerberos._tcp.<domain> (Kerberos)
  - _ldap._tcp.<domain> (LDAP)
  - <domain> SOA/NS
- Optional: test against specific DNS servers (local, other DCs, or forwarders)
- Optional: checks for broken/missing A records for this DC

WHEN TO USE
- "Cannot find domain" / logon delays / GPO failures
- Replication errors (especially RPC/1722, 1753, 1256) where DNS may be involved
- Post-migration (new DC, new DNS, site/subnet changes)
- VPN/tunnel changes impacting name resolution

NOTES
- Safe/read-only.
- Requires Resolve-DnsName (available on modern Windows).
- DNS Server log checks are handled by Get-ADCriticalEvents.ps1; this script focuses on resolution and config.
#>

[CmdletBinding()]
param(
    # AD DNS root (auto-detected if not provided)
    [string]$DomainName,

    # DNS servers to query. Default uses local machine config; optionally pass explicit servers (IP or name).
    [string[]]$DnsServers,

    # Also test the local host resolver without specifying -Server (uses Windows resolver path)
    [switch]$TestLocalResolver,

    # Include additional/verbose query set (adds gc, pdc, and msdcs NS checks)
    [switch]$IncludeExtended,

    # Check that this DC's hostname A/AAAA resolves (best-effort)
    [switch]$CheckThisDCHostRecord,

    # Return only failures (useful for automation)
    [switch]$OnlyFailures
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-DefaultDomain {
    try { (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).Domain }
    catch { $null }
}

function Get-LocalDnsClientServers {
    try {
        $items = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object { $_.ServerAddresses -and $_.ServerAddresses.Count -gt 0 } |
            Select-Object InterfaceAlias, ServerAddresses
        return $items
    } catch {
        return @()
    }
}

function Resolve-Query {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Type,
        [string]$Server,               # optional
        [string]$ResolverLabel         # label for output
    )

    try {
        $r = if ([string]::IsNullOrWhiteSpace($Server)) {
            Resolve-DnsName -Name $Name -Type $Type -ErrorAction Stop
        } else {
            Resolve-DnsName -Name $Name -Type $Type -Server $Server -ErrorAction Stop
        }

        [pscustomobject]@{
            Resolver     = $ResolverLabel
            Server       = if ($Server) { $Server } else { '(local resolver)' }
            QueryName    = $Name
            QueryType    = $Type
            Success      = $true
            Answer       = (($r | Select-Object -First 30 | Out-String).Trim())
            Error        = $null
        }
    }
    catch {
        [pscustomobject]@{
            Resolver     = $ResolverLabel
            Server       = if ($Server) { $Server } else { '(local resolver)' }
            QueryName    = $Name
            QueryType    = $Type
            Success      = $false
            Answer       = $null
            Error        = $_.Exception.Message
        }
    }
}

function Get-DnsServiceState {
    $svc = Get-Service -Name DNS -ErrorAction SilentlyContinue
    if (-not $svc) {
        return [pscustomobject]@{ Present = $false; Status = 'NotInstalled' }
    }
    [pscustomobject]@{ Present = $true; Status = $svc.Status.ToString() }
}

$computer = $env:COMPUTERNAME
$domain = if ($DomainName) { $DomainName } else { Get-DefaultDomain }
if ([string]::IsNullOrWhiteSpace($domain)) {
    throw "Unable to determine domain name. Provide -DomainName explicitly."
}

# Determine DNS servers to test
$localDnsClient = Get-LocalDnsClientServers
$resolvedDnsServers = @()

if ($DnsServers -and $DnsServers.Count -gt 0) {
    $resolvedDnsServers = $DnsServers
} else {
    # Flatten local DNS client servers into a unique list
    $resolvedDnsServers = @(
        $localDnsClient | ForEach-Object { $_.ServerAddresses } | ForEach-Object { $_ }
    ) | Where-Object { $_ } | Select-Object -Unique
}

# Core AD DNS queries
$queries = @(
    @{ Name = "_ldap._tcp.dc._msdcs.$domain"; Type = "SRV"; Purpose = "DC Locator" },
    @{ Name = "_kerberos._tcp.$domain";      Type = "SRV"; Purpose = "Kerberos" },
    @{ Name = "_ldap._tcp.$domain";          Type = "SRV"; Purpose = "LDAP" },
    @{ Name = "$domain";                      Type = "SOA"; Purpose = "Authority" },
    @{ Name = "$domain";                      Type = "NS";  Purpose = "Name servers" }
)

if ($IncludeExtended) {
    $queries += @(
        @{ Name = "_ldap._tcp.gc._msdcs.$domain"; Type = "SRV"; Purpose = "Global Catalog locator" },
        @{ Name = "_ldap._tcp.pdc._msdcs.$domain"; Type = "SRV"; Purpose = "PDC locator" },
        @{ Name = "_msdcs.$domain"; Type = "NS"; Purpose = "MSDCS delegation/zone" }
    )
}

# Run queries against each DNS server (and optionally local resolver)
$results = New-Object System.Collections.Generic.List[object]

if ($TestLocalResolver) {
    foreach ($q in $queries) {
        $r = Resolve-Query -Name $q.Name -Type $q.Type -ResolverLabel "LocalResolver ($($q.Purpose))"
        $results.Add($r) | Out-Null
    }
}

foreach ($srv in $resolvedDnsServers) {
    foreach ($q in $queries) {
        $r = Resolve-Query -Name $q.Name -Type $q.Type -Server $srv -ResolverLabel "Server ($($q.Purpose))"
        $results.Add($r) | Out-Null
    }
}

# Optional: check this DC hostname A record (best-effort)
$dcHostChecks = @()
if ($CheckThisDCHostRecord) {
    $fqdn = try {
        # Works even without AD module; on DC this is typically correct
        ([System.Net.Dns]::GetHostEntry($computer)).HostName
    } catch {
        "$computer.$domain"
    }

    # Test A (and AAAA if present)
    if ($TestLocalResolver) {
        $dcHostChecks += Resolve-Query -Name $fqdn -Type 'A' -ResolverLabel 'LocalResolver (DC Host A)'
        $dcHostChecks += Resolve-Query -Name $fqdn -Type 'AAAA' -ResolverLabel 'LocalResolver (DC Host AAAA)'
    }

    foreach ($srv in $resolvedDnsServers) {
        $dcHostChecks += Resolve-Query -Name $fqdn -Type 'A' -Server $srv -ResolverLabel "Server (DC Host A)"
        $dcHostChecks += Resolve-Query -Name $fqdn -Type 'AAAA' -Server $srv -ResolverLabel "Server (DC Host AAAA)"
    }
}

# Summaries / flags
$dnsSvc = Get-DnsServiceState
$failures = @($results | Where-Object { -not $_.Success }) + @($dcHostChecks | Where-Object { -not $_.Success })

$hasIssues = $false
$issueReasons = @()

if ($failures.Count -gt 0) {
    $hasIssues = $true
    $issueReasons += "One or more required DNS queries failed."
}

if ($dnsSvc.Present -and $dnsSvc.Status -ne 'Running') {
    # Only a definite issue if this DC is supposed to host DNS; still useful to flag
    $hasIssues = $true
    $issueReasons += "DNS Server service is present but not running."
}

# If using local DNS client settings, flag if none exist
if (-not $DnsServers -and ($resolvedDnsServers.Count -eq 0)) {
    $hasIssues = $true
    $issueReasons += "No DNS client servers found in local configuration."
}

$output = [pscustomobject]@{
    ComputerName     = $computer
    Domain           = $domain
    Timestamp        = Get-Date

    DnsService       = $dnsSvc
    LocalDnsClient   = $localDnsClient

    TestedServers    = $resolvedDnsServers
    TestedLocalResolver = [bool]$TestLocalResolver

    HasDnsIssues     = [bool]$hasIssues
    IssueReasons     = if ($issueReasons.Count -gt 0) { $issueReasons } else { @() }

    QueryResults     = $results
    DCHostRecordResults = if ($CheckThisDCHostRecord) { $dcHostChecks } else { $null }

    Failures         = $failures
}

if ($OnlyFailures) {
    return $failures
}

$output
