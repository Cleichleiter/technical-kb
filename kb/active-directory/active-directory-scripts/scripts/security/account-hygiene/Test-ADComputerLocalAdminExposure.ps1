<#
.SYNOPSIS
Audits Windows LAPS / legacy LAPS coverage and who can read local admin passwords.

.DESCRIPTION
This script is designed to be safe and "read-only".
It attempts to detect:
- Windows LAPS (msLAPS-*) presence and whether computers have LAPS passwords/expiry set
- Legacy LAPS (ms-Mcs-AdmPwd / ms-Mcs-AdmPwdExpirationTime) presence and whether values exist
- Principals that can read the password attributes via ACL (best-effort)
- Coverage summary + per-computer details

OUTPUT
Returns finding objects (Severity/Category/Check/Message/Data) suitable for the orchestrator.

.PARAMETER SearchBase
Optional DN to scope the search (e.g., "OU=Workstations,DC=contoso,DC=com").

.PARAMETER IncludeServers
Include computers with OperatingSystem containing "Server".

.PARAMETER StaleDays
If password expiration indicates stale (> StaleDays), flag.

.EXAMPLE
.\Test-ADComputerLocalAdminExposure.ps1

.EXAMPLE
.\Test-ADComputerLocalAdminExposure.ps1 -SearchBase "OU=Workstations,DC=contoso,DC=com" -StaleDays 45
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SearchBase,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeServers,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1,3650)]
    [int]$StaleDays = 60
)

$ErrorActionPreference = 'Stop'

function New-Finding {
    param(
        [Parameter(Mandatory)][ValidateSet('Critical','High','Medium','Low','Info','Warning')]
        [string]$Severity,
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Check,
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory=$false)][hashtable]$Data
    )

    [pscustomobject]@{
        Timestamp = (Get-Date).ToString('s')
        Severity  = $Severity
        Category  = $Category
        Check     = $Check
        Message   = $Message
        Data      = $Data
    }
}

function Try-ImportAD {
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        return $true
    } catch { return $false }
}

if (-not (Try-ImportAD)) {
    return New-Finding -Severity 'Warning' -Category 'AccountHygiene' -Check 'Test-ADComputerLocalAdminExposure' `
        -Message 'ActiveDirectory module not available. Run from a domain-joined admin workstation/server with RSAT.' `
        -Data @{ Module = 'ActiveDirectory' }
}

# Attribute detection (Windows LAPS vs legacy LAPS)
$schemaAttrs = @('msLAPS-Password','msLAPS-PasswordExpirationTime','ms-Mcs-AdmPwd','ms-Mcs-AdmPwdExpirationTime')
$attrExists = @{}

foreach ($a in $schemaAttrs) {
    try {
        $null = Get-ADObject -LDAPFilter "(lDAPDisplayName=$a)" -SearchBase (Get-ADRootDSE).schemaNamingContext -ErrorAction Stop -Properties lDAPDisplayName
        $attrExists[$a] = $true
    } catch {
        $attrExists[$a] = $false
    }
}

$hasWinLaps   = $attrExists['msLAPS-Password'] -and $attrExists['msLAPS-PasswordExpirationTime']
$hasLegacyLaps= $attrExists['ms-Mcs-AdmPwd'] -and $attrExists['ms-Mcs-AdmPwdExpirationTime']

if (-not $hasWinLaps -and -not $hasLegacyLaps) {
    return New-Finding -Severity 'Info' -Category 'AccountHygiene' -Check 'Test-ADComputerLocalAdminExposure' `
        -Message 'No LAPS schema attributes detected (Windows LAPS or legacy LAPS). Nothing to report.' `
        -Data @{ WindowsLAPS = $false; LegacyLAPS = $false }
}

# Query computers
$props = @('OperatingSystem','LastLogonDate','Enabled')
if ($hasWinLaps)   { $props += @('msLAPS-PasswordExpirationTime') }
if ($hasLegacyLaps){ $props += @('ms-Mcs-AdmPwdExpirationTime') }

$filter = if ($IncludeServers) { '*' } else { 'OperatingSystem -notlike "*Server*"' }

$adParams = @{
    Filter      = $filter
    Properties  = $props
}
if ($SearchBase) { $adParams.SearchBase = $SearchBase }

$computers = Get-ADComputer @adParams

# Evaluate coverage
$now = Get-Date
$staleCutoff = $now.AddDays(-$StaleDays)

$results = foreach ($c in $computers) {
    $winExp = $null
    $legExp = $null

    if ($hasWinLaps) {
        # Windows LAPS expiration stored as "LargeInteger" in AD; AD module typically converts to DateTime.
        $winExp = $c.'msLAPS-PasswordExpirationTime'
    }
    if ($hasLegacyLaps) {
        $legExp = $c.'ms-Mcs-AdmPwdExpirationTime'
    }

    $lapsType = if ($winExp) { 'WindowsLAPS' } elseif ($legExp) { 'LegacyLAPS' } else { 'None' }
    $exp      = if ($winExp) { $winExp } elseif ($legExp) { $legExp } else { $null }

    $stale = $false
    if ($exp) {
        try { if ($exp -lt $staleCutoff) { $stale = $true } } catch {}
    }

    [pscustomobject]@{
        ComputerName   = $c.Name
        Enabled        = $c.Enabled
        OperatingSystem= $c.OperatingSystem
        LastLogonDate  = $c.LastLogonDate
        LapsType       = $lapsType
        PasswordExpiry = $exp
        IsStale        = $stale
    }
}

$total = $results.Count
$withLaps = ($results | Where-Object { $_.LapsType -ne 'None' }).Count
$withoutLaps = $total - $withLaps
$staleCount = ($results | Where-Object { $_.IsStale -eq $true }).Count

$findings = New-Object System.Collections.Generic.List[object]

# Summary finding
$findings.Add((New-Finding -Severity 'Info' -Category 'AccountHygiene' -Check 'Test-ADComputerLocalAdminExposure' `
    -Message "LAPS coverage summary: Total=$total, WithLAPS=$withLaps, WithoutLAPS=$withoutLaps, Stale(>$StaleDays days)=$staleCount." `
    -Data @{
        Total         = $total
        WithLAPS      = $withLaps
        WithoutLAPS   = $withoutLaps
        StaleCount    = $staleCount
        StaleDays     = $StaleDays
        WindowsLAPS   = $hasWinLaps
        LegacyLAPS    = $hasLegacyLaps
        SearchBase    = $SearchBase
        IncludeServers= [bool]$IncludeServers
    })) | Out-Null

if ($withoutLaps -gt 0) {
    $sev = if ($withoutLaps -gt [math]::Ceiling($total * 0.25)) { 'High' } else { 'Medium' }
    $sample = $results | Where-Object { $_.LapsType -eq 'None' } | Select-Object -First 50
    $findings.Add((New-Finding -Severity $sev -Category 'AccountHygiene' -Check 'LAPS-Coverage' `
        -Message "One or more computers do not appear to have Windows LAPS or legacy LAPS password metadata set. Validate LAPS deployment and policy targeting." `
        -Data @{ Count = $withoutLaps; Sample = $sample })) | Out-Null
}

if ($staleCount -gt 0) {
    $sample = $results | Where-Object { $_.IsStale -eq $true } | Sort-Object PasswordExpiry | Select-Object -First 50
    $findings.Add((New-Finding -Severity 'Medium' -Category 'AccountHygiene' -Check 'LAPS-Stale' `
        -Message "Some computers show LAPS password expiry older than $StaleDays days. Validate rotation and client health." `
        -Data @{ Count = $staleCount; Sample = $sample })) | Out-Null
}

# Optional: try to identify who can read the attribute at root of the domain (best-effort)
# This is not perfect (effective rights vary), but can still surface obvious misconfig (e.g., Authenticated Users).
try {
    $domainDn = (Get-ADDomain).DistinguishedName
    $acl = Get-Acl -Path ("AD:$domainDn")

    $attrGuidToCheck = @()
    if ($hasWinLaps) {
        # msLAPS-Password is confidential; if delegated incorrectly it is severe. We look for broad ACEs that grant ReadProperty.
        $attr = Get-ADObject -LDAPFilter "(lDAPDisplayName=msLAPS-Password)" -SearchBase (Get-ADRootDSE).schemaNamingContext -Properties schemaIDGUID
        if ($attr.schemaIDGUID) { $attrGuidToCheck += [Guid]$attr.schemaIDGUID }
    }
    if ($hasLegacyLaps) {
        $attr = Get-ADObject -LDAPFilter "(lDAPDisplayName=ms-Mcs-AdmPwd)" -SearchBase (Get-ADRootDSE).schemaNamingContext -Properties schemaIDGUID
        if ($attr.schemaIDGUID) { $attrGuidToCheck += [Guid]$attr.schemaIDGUID }
    }

    if ($attrGuidToCheck.Count -gt 0) {
        $risky = foreach ($ace in $acl.Access) {
            # Look for broad identities with ReadProperty rights (best-effort)
            if ($ace.ActiveDirectoryRights.ToString().Contains('ReadProperty')) {
                if ($ace.IdentityReference -match 'Authenticated Users|Everyone|Domain Users') {
                    [pscustomobject]@{
                        Identity  = [string]$ace.IdentityReference
                        Rights    = [string]$ace.ActiveDirectoryRights
                        Type      = [string]$ace.AccessControlType
                        Inherited = [bool]$ace.IsInherited
                        ObjectType= [string]$ace.ObjectType
                    }
                }
            }
        }

        if ($risky) {
            $findings.Add((New-Finding -Severity 'High' -Category 'AccountHygiene' -Check 'LAPS-ReadPermissions' `
                -Message "Broad principals appear to have ReadProperty rights that may allow reading LAPS password attributes (best-effort ACL check). Review delegated permissions for LAPS readers." `
                -Data @{ RiskyAces = $risky })) | Out-Null
        }
    }
} catch {
    $findings.Add((New-Finding -Severity 'Info' -Category 'AccountHygiene' -Check 'LAPS-ReadPermissions' `
        -Message "Could not evaluate domain ACLs for LAPS readers (best-effort). Run with appropriate rights or validate manually." `
        -Data @{ Error = $_.Exception.Message })) | Out-Null
}

$findings
