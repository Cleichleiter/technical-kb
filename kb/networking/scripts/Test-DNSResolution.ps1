# Test-DNSResolution.ps1
<#
.SYNOPSIS
Tests DNS resolution against configured DNS servers and optional explicit servers.

.DESCRIPTION
Validates:
- Local resolver behavior
- Per-DNS-server responsiveness
- A/AAAA resolution results and timing (best-effort)

.PARAMETER Targets
One or more DNS names to resolve.

.PARAMETER DnsServers
Optional explicit DNS servers to query. If not provided, uses DNS servers from all active adapters.

.PARAMETER RecordType
DNS record type to query (A, AAAA, CNAME, etc.). Defaults to A.

.PARAMETER TimeoutSeconds
Per-query timeout.

.NOTES
Read-only. Safe for production.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]]$Targets,

    [string[]]$DnsServers,

    [ValidateSet('A','AAAA','CNAME','MX','TXT','SRV','NS','PTR')]
    [string]$RecordType = 'A',

    [ValidateRange(1,30)]
    [int]$TimeoutSeconds = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Discover DNS servers if not specified
if (-not $DnsServers -or $DnsServers.Count -eq 0) {
    $DnsServers = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.ServerAddresses } |
        ForEach-Object { $_.ServerAddresses } |
        Where-Object { $_ } |
        Select-Object -Unique
}

$localResults = New-Object System.Collections.Generic.List[object]
$perServerResults = New-Object System.Collections.Generic.List[object]
$issues = New-Object System.Collections.Generic.List[string]

# Local resolver check (no explicit server)
foreach ($t in $Targets) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $r = Resolve-DnsName -Name $t -Type $RecordType -ErrorAction Stop
        $sw.Stop()
        $ips = $r | Where-Object { $_.IPAddress } | Select-Object -ExpandProperty IPAddress -Unique
        $localResults.Add([pscustomobject]@{
            Target     = $t
            Type       = $RecordType
            Status     = 'PASS'
            DurationMs = [int]$sw.ElapsedMilliseconds
            Answers    = $ips
            Error      = $null
        }) | Out-Null
    } catch {
        $sw.Stop()
        $localResults.Add([pscustomobject]@{
            Target     = $t
            Type       = $RecordType
            Status     = 'FAIL'
            DurationMs = [int]$sw.ElapsedMilliseconds
            Answers    = @()
            Error      = $_.Exception.Message
        }) | Out-Null
        $issues.Add("Local DNS resolution failed for: $t") | Out-Null
    }
}

# Per-server checks
foreach ($s in ($DnsServers | Where-Object { $_ })) {
    foreach ($t in $Targets) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $r = Resolve-DnsName -Name $t -Type $RecordType -Server $s -QuickTimeout -ErrorAction Stop
            $sw.Stop()
            $ips = $r | Where-Object { $_.IPAddress } | Select-Object -ExpandProperty IPAddress -Unique
            $perServerResults.Add([pscustomobject]@{
                DnsServer  = $s
                Target     = $t
                Type       = $RecordType
                Status     = 'PASS'
                DurationMs = [int]$sw.ElapsedMilliseconds
                Answers    = $ips
                Error      = $null
            }) | Out-Null
        } catch {
            $sw.Stop()
            $perServerResults.Add([pscustomobject]@{
                DnsServer  = $s
                Target     = $t
                Type       = $RecordType
                Status     = 'FAIL'
                DurationMs = [int]$sw.ElapsedMilliseconds
                Answers    = @()
                Error      = $_.Exception.Message
            }) | Out-Null
            $issues.Add("DNS server $s failed to resolve $t") | Out-Null
        }
    }
}

# Flag if any configured DNS server is consistently failing
$serverFailRate = $perServerResults |
    Group-Object DnsServer |
    ForEach-Object {
        $total = $_.Count
        $fails = @($_.Group | Where-Object { $_.Status -eq 'FAIL' }).Count
        [pscustomobject]@{
            DnsServer = $_.Name
            Total     = $total
            Failed    = $fails
            FailRate  = if ($total -gt 0) { [math]::Round(($fails / $total), 2) } else { 0 }
        }
    } | Sort-Object FailRate -Descending

foreach ($s in $serverFailRate) {
    if ($s.FailRate -ge 0.5 -and $s.Total -ge 2) {
        $issues.Add("DNS server $($s.DnsServer) is failing >= 50% of queries (FailRate=$($s.FailRate)).") | Out-Null
    }
}

[pscustomobject]@{
    Check        = 'DNSResolution'
    Timestamp    = Get-Date
    RecordType   = $RecordType
    Targets      = $Targets
    DnsServers   = $DnsServers
    LocalResults = $localResults
    PerServerResults = $perServerResults
    ServerFailureSummary = $serverFailRate
    HasIssues    = [bool]($issues.Count -gt 0)
    IssueReasons = $issues
}
