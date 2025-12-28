<#
.SYNOPSIS
Reports network adapter binding state (IPv4/IPv6 and common client/protocol bindings).

.DESCRIPTION
Useful for diagnosing:
- IPv6 disabled in ways that break modern Windows networking
- Missing Client for Microsoft Networks / File and Printer Sharing
- Unexpected bindings enabled/disabled across adapters

.PARAMETER IncludeAllAdapters
Include non-up adapters (default is only Up adapters).

.NOTES
Read-only. Safe for production.
#>

[CmdletBinding()]
param(
    [switch]$IncludeAllAdapters
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$issues = New-Object System.Collections.Generic.List[string]

$adapters = Get-NetAdapter -ErrorAction Stop
if (-not $IncludeAllAdapters) {
    $adapters = $adapters | Where-Object { $_.Status -eq 'Up' }
}

$results = foreach ($a in $adapters) {
    $bindings = $null
    try {
        $bindings = Get-NetAdapterBinding -Name $a.Name -ErrorAction Stop |
            Select-Object ComponentID, DisplayName, Enabled
    } catch {
        $bindings = @([pscustomobject]@{ Error = $_.Exception.Message })
    }

    # Common signals
    $b = @($bindings)
    $ipv4 = $b | Where-Object { $_.ComponentID -eq 'ms_tcpip' } | Select-Object -First 1
    $ipv6 = $b | Where-Object { $_.ComponentID -eq 'ms_tcpip6' } | Select-Object -First 1
    $client = $b | Where-Object { $_.ComponentID -eq 'ms_msclient' } | Select-Object -First 1
    $srv = $b | Where-Object { $_.ComponentID -eq 'ms_server' } | Select-Object -First 1

    if ($ipv4 -and $ipv4.Enabled -eq $false) {
        $issues.Add("IPv4 binding disabled on adapter '$($a.Name)' (ms_tcpip).") | Out-Null
    }
    if ($client -and $client.Enabled -eq $false) {
        $issues.Add("Client for Microsoft Networks disabled on adapter '$($a.Name)' (ms_msclient).") | Out-Null
    }
    if ($srv -and $srv.Enabled -eq $false) {
        $issues.Add("File and Printer Sharing disabled on adapter '$($a.Name)' (ms_server).") | Out-Null
    }

    [pscustomobject]@{
        AdapterName  = $a.Name
        Status       = $a.Status
        ifIndex      = $a.ifIndex
        Description  = $a.InterfaceDescription
        Bindings     = $bindings
        IPv4Enabled  = if ($ipv4) { [bool]$ipv4.Enabled } else { $null }
        IPv6Enabled  = if ($ipv6) { [bool]$ipv6.Enabled } else { $null }
        ClientEnabled= if ($client) { [bool]$client.Enabled } else { $null }
        ServerEnabled= if ($srv) { [bool]$srv.Enabled } else { $null }
    }
}

[pscustomobject]@{
    Check        = 'NetworkBindings'
    Timestamp    = Get-Date
    Results      = $results
    HasIssues    = [bool]($issues.Count -gt 0)
    IssueReasons = $issues
}
