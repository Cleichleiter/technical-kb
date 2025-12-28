# Get-NetworkConfiguration.ps1
<#
.SYNOPSIS
Captures a structured snapshot of local network configuration.

.DESCRIPTION
Collects:
- Adapter inventory (status, link speed, MAC)
- IP configuration (IPv4/IPv6 addresses, gateways)
- DNS servers, DNS suffix/search list
- DHCP status per interface
- Proxy settings (WinHTTP + IE/WinINET)
- Hosts file presence and last write time (no content by default)

.PARAMETER IncludeHostsFilePreview
If set, includes the first N non-empty, non-comment lines from hosts file.

.PARAMETER HostsPreviewLines
Number of hosts file lines to include if preview is enabled.

.NOTES
Read-only. Safe for production. No secrets collected.
#>

[CmdletBinding()]
param(
    [switch]$IncludeHostsFilePreview,
    [ValidateRange(1,200)]
    [int]$HostsPreviewLines = 25
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$adapters = Get-NetAdapter -ErrorAction Stop |
    Select-Object Name, InterfaceDescription, Status, MacAddress, LinkSpeed, ifIndex, DriverInformation

$ipConfigs = Get-NetIPConfiguration -ErrorAction Stop | ForEach-Object {
    [pscustomobject]@{
        InterfaceAlias  = $_.InterfaceAlias
        InterfaceIndex  = $_.InterfaceIndex
        IPv4Addresses   = @($_.IPv4Address | ForEach-Object { $_.IPAddress }) | Where-Object { $_ }
        IPv6Addresses   = @($_.IPv6Address | ForEach-Object { $_.IPAddress }) | Where-Object { $_ }
        IPv4Gateway     = @($_.IPv4DefaultGateway | ForEach-Object { $_.NextHop }) | Where-Object { $_ }
        IPv6Gateway     = @($_.IPv6DefaultGateway | ForEach-Object { $_.NextHop }) | Where-Object { $_ }
        DnsServersV4    = @($_.DnsServer.ServerAddresses) | Where-Object { $_ -and ($_ -match '^\d{1,3}(\.\d{1,3}){3}$') }
        DnsServersV6    = @($_.DnsServer.ServerAddresses) | Where-Object { $_ -and ($_ -match ':') }
        DnsSuffix       = $_.NetProfile.DnsSuffix
        ConnectionProfile = $_.NetProfile.Name
        NetworkCategory = $_.NetProfile.NetworkCategory
        IPv4Interface   = try { Get-NetIPInterface -InterfaceIndex $_.InterfaceIndex -AddressFamily IPv4 -ErrorAction Stop } catch { $null }
        IPv6Interface   = try { Get-NetIPInterface -InterfaceIndex $_.InterfaceIndex -AddressFamily IPv6 -ErrorAction Stop } catch { $null }
    }
}

$dnsClient = Get-DnsClient -ErrorAction SilentlyContinue |
    Select-Object SuffixSearchList, UseSuffixWhenRegistering, RegisterThisConnectionsAddress, ConnectionSpecificSuffix

$globalDns = Get-DnsClientGlobalSetting -ErrorAction SilentlyContinue |
    Select-Object SuffixSearchList, UseDevolution, DevolutionLevel

$winhttpProxy = $null
try {
    $winhttpProxy = & netsh winhttp show proxy 2>&1
} catch { }

$ieProxy = $null
try {
    $reg = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    if (Test-Path -LiteralPath $reg) {
        $p = Get-ItemProperty -LiteralPath $reg -ErrorAction Stop
        $ieProxy = [pscustomobject]@{
            ProxyEnable  = $p.ProxyEnable
            ProxyServer  = $p.ProxyServer
            ProxyOverride= $p.ProxyOverride
            AutoConfigURL= $p.AutoConfigURL
        }
    }
} catch { }

$hostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
$hostsInfo = $null
if (Test-Path -LiteralPath $hostsPath) {
    $fi = Get-Item -LiteralPath $hostsPath -ErrorAction SilentlyContinue
    $hostsInfo = [pscustomobject]@{
        Path          = $hostsPath
        Exists        = $true
        LastWriteTime = $fi.LastWriteTime
        LengthBytes   = $fi.Length
        Preview       = $null
    }

    if ($IncludeHostsFilePreview) {
        $preview = Get-Content -LiteralPath $hostsPath -ErrorAction SilentlyContinue |
            Where-Object { $_ -and $_.Trim() -ne '' -and -not $_.Trim().StartsWith('#') } |
            Select-Object -First $HostsPreviewLines
        $hostsInfo.Preview = $preview
    }
} else {
    $hostsInfo = [pscustomobject]@{
        Path          = $hostsPath
        Exists        = $false
        LastWriteTime = $null
        LengthBytes   = $null
        Preview       = $null
    }
}

[pscustomobject]@{
    Check        = 'NetworkConfiguration'
    Timestamp    = Get-Date
    ComputerName = $env:COMPUTERNAME
    Adapters     = $adapters
    IPConfiguration = $ipConfigs
    DnsClient    = $dnsClient
    DnsGlobal    = $globalDns
    Proxy = [pscustomobject]@{
        WinHTTP = $winhttpProxy
        IE      = $ieProxy
    }
    HostsFile    = $hostsInfo
}
