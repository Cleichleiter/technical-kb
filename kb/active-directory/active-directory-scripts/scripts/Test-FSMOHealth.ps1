<#
.SYNOPSIS
Runs FSMO migration pre-flight checks for a target DC.

.DESCRIPTION
Use BEFORE transferring roles to confirm:
- DC exists and is reachable
- ADWS is responsive (basic AD cmdlets can query it)
- Replication health is reasonable
- Time service sanity (for PDC moves)
- Target DC is writable (not RODC)
- DC is a GC (recommended when moving Infrastructure in single-domain; required depends on topology)

.PARAMETER TargetDC
The DC you intend to move FSMO roles to.

.PARAMETER Domain
Optional. Domain DNS name.

.EXAMPLE
.\Test-FSMOHealth.ps1 -TargetDC DC02.contoso.com -Verbose
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TargetDC,
    [string]$Domain
)

$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory -ErrorAction Stop

function New-CheckResult {
    param([string]$Name,[string]$Status,[string]$Details)
    [pscustomobject]@{
        Check   = $Name
        Status  = $Status
        Details = $Details
        TimeUtc = (Get-Date).ToUniversalTime()
    }
}

$results = New-Object System.Collections.Generic.List[object]

# Resolve DC object
try {
    $dc = Get-ADDomainController -Identity $TargetDC -ErrorAction Stop
    $results.Add((New-CheckResult -Name 'Target DC resolves' -Status 'PASS' -Details $dc.HostName))
} catch {
    $results.Add((New-CheckResult -Name 'Target DC resolves' -Status 'FAIL' -Details $_.Exception.Message))
    $results
    return
}

# Basic connectivity
try {
    $ping = Test-Connection -ComputerName $dc.HostName -Count 2 -Quiet -ErrorAction Stop
    $results.Add((New-CheckResult -Name 'ICMP reachable' -Status ($ping ? 'PASS' : 'WARN') -Details "Ping=$ping"))
} catch {
    $results.Add((New-CheckResult -Name 'ICMP reachable' -Status 'WARN' -Details $_.Exception.Message))
}

# ADWS/LDAP basic query (proof the AD module can talk to it)
try {
    $null = Get-ADRootDSE -Server $dc.HostName -ErrorAction Stop
    $results.Add((New-CheckResult -Name 'ADWS/LDAP query' -Status 'PASS' -Details 'Get-ADRootDSE succeeded'))
} catch {
    $results.Add((New-CheckResult -Name 'ADWS/LDAP query' -Status 'FAIL' -Details $_.Exception.Message))
}

# RODC check
if ($dc.IsReadOnly) {
    $results.Add((New-CheckResult -Name 'Writable DC' -Status 'FAIL' -Details 'Target is an RODC (cannot hold FSMO roles).'))
} else {
    $results.Add((New-CheckResult -Name 'Writable DC' -Status 'PASS' -Details 'Target is writable.'))
}

# Global Catalog check (context-dependent but commonly important)
$results.Add((New-CheckResult -Name 'Global Catalog' -Status ($dc.IsGlobalCatalog ? 'PASS' : 'WARN') -Details ("IsGC=" + $dc.IsGlobalCatalog)))

# Replication: failures for last 24h (lightweight, fast signal)
try {
    $since = (Get-Date).AddHours(-24)
    $fail = Get-ADReplicationFailure -Target $dc.HostName -Scope Server -ErrorAction Stop |
        Where-Object { $_.FirstFailureTime -ge $since }

    if ($fail) {
        $results.Add((New-CheckResult -Name 'Replication failures (24h)' -Status 'WARN' -Details ("Count=" + $fail.Count)))
    } else {
        $results.Add((New-CheckResult -Name 'Replication failures (24h)' -Status 'PASS' -Details 'None in last 24 hours (per Get-ADReplicationFailure).'))
    }
} catch {
    $results.Add((New-CheckResult -Name 'Replication failures (24h)' -Status 'WARN' -Details $_.Exception.Message))
}

# Time sanity (PDC move especially). This is a quick read; not a full time audit.
try {
    $w32 = & w32tm /query /computer:$dc.HostName /status 2>&1
    if ($LASTEXITCODE -eq 0) {
        $results.Add((New-CheckResult -Name 'W32Time status' -Status 'PASS' -Details 'w32tm /query /status succeeded'))
    } else {
        $results.Add((New-CheckResult -Name 'W32Time status' -Status 'WARN' -Details ($w32 | Select-Object -First 1)))
    }
} catch {
    $results.Add((New-CheckResult -Name 'W32Time status' -Status 'WARN' -Details $_.Exception.Message))
}

# Optional domain context
try {
    $domainObj = if ($Domain) { Get-ADDomain -Identity $Domain } else { Get-ADDomain }
    $results.Add((New-CheckResult -Name 'Domain context' -Status 'PASS' -Details $domainObj.DNSRoot))
} catch {
    $results.Add((New-CheckResult -Name 'Domain context' -Status 'WARN' -Details $_.Exception.Message))
}

$results
