# Test-PortConnectivity.ps1
<#
.SYNOPSIS
Tests TCP/UDP connectivity to a target and port list.

.DESCRIPTION
Supports:
- TCP tests using Test-NetConnection (preferred)
- UDP "best-effort" tests (cannot reliably prove open without application response)

Use cases:
- Validating app dependencies (SQL, RDP, SMB, LDAP, HTTPS)
- Troubleshooting "can’t connect" incidents
- Pre-migration validation of server reachability

.PARAMETER Target
Hostname or IP.

.PARAMETER TcpPorts
TCP ports to test.

.PARAMETER UdpPorts
UDP ports to test (best-effort).

.PARAMETER TimeoutSeconds
Timeout for TCP connect attempts.

.PARAMETER ResolveDns
If set, resolves the target before tests and includes DNS details.

.NOTES
Read-only. Safe for production.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Target,

    [int[]]$TcpPorts = @(),

    [int[]]$UdpPorts = @(),

    [ValidateRange(1,30)]
    [int]$TimeoutSeconds = 3,

    [switch]$ResolveDns
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$issues = New-Object System.Collections.Generic.List[string]

$dns = $null
if ($ResolveDns) {
    try {
        $dns = Resolve-DnsName -Name $Target -ErrorAction Stop |
            Select-Object -First 10 |
            Select-Object Name, Type, IPAddress
    } catch {
        $dns = [pscustomobject]@{ Error = $_.Exception.Message }
        $issues.Add("DNS resolution failed for target $Target.") | Out-Null
    }
}

$tcpResults = New-Object System.Collections.Generic.List[object]
foreach ($p in ($TcpPorts | Where-Object { $_ -gt 0 } | Select-Object -Unique)) {
    try {
        $r = Test-NetConnection -ComputerName $Target -Port $p -InformationLevel Detailed -WarningAction SilentlyContinue -ErrorAction Stop

        $tcpResults.Add([pscustomobject]@{
            Target        = $Target
            Protocol      = 'TCP'
            Port          = $p
            Success       = [bool]$r.TcpTestSucceeded
            RemoteAddress = $r.RemoteAddress
            SourceAddress = $r.SourceAddress
            PingSucceeded = $r.PingSucceeded
            PingReplyDetails = $r.PingReplyDetails
            Error         = $null
        }) | Out-Null

        if (-not $r.TcpTestSucceeded) {
            $issues.Add("TCP port test failed: $Target:$p") | Out-Null
        }
    } catch {
        $tcpResults.Add([pscustomobject]@{
            Target        = $Target
            Protocol      = 'TCP'
            Port          = $p
            Success       = $false
            RemoteAddress = $null
            SourceAddress = $null
            PingSucceeded = $null
            PingReplyDetails = $null
            Error         = $_.Exception.Message
        }) | Out-Null

        $issues.Add("TCP port test errored: $Target:$p ($($_.Exception.Message))") | Out-Null
    }
}

# UDP tests are inherently best-effort without app-level response.
# Here we attempt a UDP "send" and report that send was attempted; it does not prove port is open.
$udpResults = New-Object System.Collections.Generic.List[object]
foreach ($p in ($UdpPorts | Where-Object { $_ -gt 0 } | Select-Object -Unique)) {
    $ok = $false
    $err = $null
    try {
        $client = New-Object System.Net.Sockets.UdpClient
        $client.Client.SendTimeout = $TimeoutSeconds * 1000
        $client.Connect($Target, $p) | Out-Null

        $bytes = [System.Text.Encoding]::ASCII.GetBytes('ping')
        [void]$client.Send($bytes, $bytes.Length)
        $client.Close()
        $ok = $true
    } catch {
        $ok = $false
        $err = $_.Exception.Message
    }

    $udpResults.Add([pscustomobject]@{
        Target   = $Target
        Protocol = 'UDP'
        Port     = $p
        SendAttempted = $ok
        Note     = 'UDP results are best-effort; a successful send does not confirm the port is open.'
        Error    = $err
    }) | Out-Null

    if (-not $ok) {
        $issues.Add("UDP send attempt failed: $Target:$p") | Out-Null
    }
}

[pscustomobject]@{
    Check        = 'PortConnectivity'
    Timestamp    = Get-Date
    Target       = $Target
    Dns          = $dns
    TcpPorts     = $TcpPorts
    UdpPorts     = $UdpPorts
    TcpResults   = $tcpResults
    UdpResults   = $udpResults
    HasIssues    = [bool]($issues.Count -gt 0)
    IssueReasons = $issues
}
