# Get-TcpipStatistics.ps1
<#
.SYNOPSIS
Captures TCP/IP stack statistics to support diagnosing retransmits, resets, and errors.

.DESCRIPTION
Collects:
- Get-NetTCPStatistics
- Get-NetUDPEndpoint counts (optional)
- Interface stats (bytes/packets/errors/discards) via Get-NetAdapterStatistics

.PARAMETER IncludeEndpoints
If set, includes top-level endpoint counts (not full listings).

.NOTES
Read-only. Safe for production.
#>

[CmdletBinding()]
param(
    [switch]$IncludeEndpoints
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$issues = New-Object System.Collections.Generic.List[string]

$tcpStats = $null
try {
    $tcpStats = Get-NetTCPStatistics -ErrorAction Stop
} catch {
    $tcpStats = [pscustomobject]@{ Error = $_.Exception.Message }
}

# Adapter statistics (errors/discards are high-signal)
$adapterStats = @()
try {
    $adapterStats = Get-NetAdapterStatistics -ErrorAction Stop |
        Select-Object Name, ReceivedBytes, SentBytes, ReceivedUnicastPackets, SentUnicastPackets, `
                      ReceivedDiscardedPackets, SentDiscardedPackets, ReceivedPacketErrors, SentPacketErrors
} catch {
    $adapterStats = [pscustomobject]@{ Error = $_.Exception.Message }
}

# Flag packet errors/discards if present
if ($adapterStats -is [System.Array]) {
    foreach ($a in $adapterStats) {
        if (($a.ReceivedPacketErrors + $a.SentPacketErrors) -gt 0) {
            $issues.Add("Packet errors detected on adapter '$($a.Name)' (RxErr=$($a.ReceivedPacketErrors), TxErr=$($a.SentPacketErrors)).") | Out-Null
        }
        if (($a.ReceivedDiscardedPackets + $a.SentDiscardedPackets) -gt 0) {
            $issues.Add("Packet discards detected on adapter '$($a.Name)' (RxDisc=$($a.ReceivedDiscardedPackets), TxDisc=$($a.SentDiscardedPackets)).") | Out-Null
        }
    }
}

# Endpoint counts (optional, avoids dumping full connection lists)
$endpointCounts = $null
if ($IncludeEndpoints) {
    try {
        $tcpListen = (Get-NetTCPConnection -State Listen -ErrorAction Stop).Count
        $tcpEstab  = (Get-NetTCPConnection -State Established -ErrorAction Stop).Count
        $udpCount  = (Get-NetUDPEndpoint -ErrorAction Stop).Count

        $endpointCounts = [pscustomobject]@{
            TcpListening   = $tcpListen
            TcpEstablished = $tcpEstab
            UdpEndpoints   = $udpCount
        }
    } catch {
        $endpointCounts = [pscustomobject]@{ Error = $_.Exception.Message }
    }
}

[pscustomobject]@{
    Check        = 'TcpipStatistics'
    Timestamp    = Get-Date
    TcpStatistics = $tcpStats
    AdapterStatistics = $adapterStats
    EndpointCounts = $endpointCounts
    HasIssues    = [bool]($issues.Count -gt 0)
    IssueReasons = $issues
}
