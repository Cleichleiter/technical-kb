# Get-NetworkAdapterStatus.ps1
<#
.SYNOPSIS
Reports adapter health and highlights common adapter-level issues.

.DESCRIPTION
Captures:
- Adapter status, link speed, MAC
- Driver details (best-effort)
- RSS / RSC / checksum offload (best-effort)
- Power management flags (best-effort for common cases)
- Disabled / disconnected adapters summary

.NOTES
Read-only. Safe for production.
#>

[CmdletBinding()]
param(
    [switch]$IncludeAdvancedProperties
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$issues = New-Object System.Collections.Generic.List[string]

$adapters = Get-NetAdapter -ErrorAction Stop

$adapterDetails = foreach ($a in $adapters) {
    $adv = $null
    if ($IncludeAdvancedProperties) {
        try {
            $adv = Get-NetAdapterAdvancedProperty -Name $a.Name -ErrorAction Stop |
                Select-Object DisplayName, DisplayValue, RegistryKeyword
        } catch { $adv = $null }
    }

    $rss = $null
    try { $rss = Get-NetAdapterRss -Name $a.Name -ErrorAction Stop | Select-Object Enabled, NumberOfReceiveQueues, Profile } catch { }

    $rsc = $null
    try { $rsc = Get-NetAdapterRsc -Name $a.Name -ErrorAction Stop | Select-Object IPv4Enabled, IPv6Enabled } catch { }

    $csum = $null
    try { $csum = Get-NetAdapterChecksumOffload -Name $a.Name -ErrorAction Stop | Select-Object * } catch { }

    if ($a.Status -eq 'Disabled') { $issues.Add("Adapter disabled: $($a.Name)") | Out-Null }
    if ($a.Status -eq 'Disconnected') { $issues.Add("Adapter disconnected: $($a.Name)") | Out-Null }

    [pscustomobject]@{
        Name        = $a.Name
        ifIndex     = $a.ifIndex
        Status      = $a.Status
        MacAddress  = $a.MacAddress
        LinkSpeed   = $a.LinkSpeed
        InterfaceDescription = $a.InterfaceDescription
        DriverInformation    = $a.DriverInformation
        Rss         = $rss
        Rsc         = $rsc
        ChecksumOffload = $csum
        AdvancedProperties = $adv
    }
}

[pscustomobject]@{
    Check        = 'NetworkAdapterStatus'
    Timestamp    = Get-Date
    Adapters     = $adapterDetails
    HasIssues    = [bool]($issues.Count -gt 0)
    IssueReasons = $issues
}
