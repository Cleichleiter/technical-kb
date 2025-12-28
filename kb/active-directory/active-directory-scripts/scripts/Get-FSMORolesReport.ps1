<#
.SYNOPSIS
Reports current FSMO role holders (forest + domain), plus basic DC metadata.

.DESCRIPTION
Use this to quickly document:
- Schema Master
- Domain Naming Master
- PDC Emulator
- RID Master
- Infrastructure Master

Includes some context (site, OS, GC) to help with migration planning.

.PARAMETER Domain
Optional. Target domain DNS name. Defaults to current domain.

.PARAMETER IncludeDCDetails
Include DC inventory details for the domain/forest.

.EXAMPLE
.\Get-FSMORolesReport.ps1 | Format-List

.EXAMPLE
.\Get-FSMORolesReport.ps1 -IncludeDCDetails | Export-Csv .\FSMO-Report.csv -NoTypeInformation
#>

[CmdletBinding()]
param(
    [string]$Domain,
    [switch]$IncludeDCDetails
)

$ErrorActionPreference = 'Stop'

function Resolve-HostFqdn {
    param([string]$Name)
    try {
        return ([System.Net.Dns]::GetHostEntry($Name)).HostName
    } catch {
        return $Name
    }
}

Import-Module ActiveDirectory -ErrorAction Stop

$forest = Get-ADForest
$domainObj = if ($Domain) { Get-ADDomain -Identity $Domain } else { Get-ADDomain }

$forestRoles = [pscustomobject]@{
    Scope                = 'Forest'
    Forest               = $forest.Name
    SchemaMaster         = Resolve-HostFqdn $forest.SchemaMaster
    DomainNamingMaster   = Resolve-HostFqdn $forest.DomainNamingMaster
    TimestampUtc         = (Get-Date).ToUniversalTime()
}

$domainRoles = [pscustomobject]@{
    Scope               = 'Domain'
    Domain              = $domainObj.DNSRoot
    PDCEmulator         = Resolve-HostFqdn $domainObj.PDCEmulator
    RIDMaster           = Resolve-HostFqdn $domainObj.RIDMaster
    InfrastructureMaster= Resolve-HostFqdn $domainObj.InfrastructureMaster
    TimestampUtc        = (Get-Date).ToUniversalTime()
}

$results = @($forestRoles, $domainRoles)

if ($IncludeDCDetails) {
    $dcs = Get-ADDomainController -Filter * -Server $domainObj.DNSRoot |
        Select-Object `
            @{n='Scope';e={'DC'}},
            @{n='Domain';e={$domainObj.DNSRoot}},
            HostName, IPv4Address, Site, IsGlobalCatalog, IsReadOnly,
            OperatingSystem, OperatingSystemVersion,
            @{n='TimestampUtc';e={(Get-Date).ToUniversalTime()}}

    $results += $dcs
}

$results
