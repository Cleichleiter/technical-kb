<#
.SYNOPSIS
Detects principals with DCSync-equivalent replication extended rights on the domain root.

.DESCRIPTION
Read-only check of the domain root ACL for the replication extended rights commonly associated with DCSync:
- DS-Replication-Get-Changes
- DS-Replication-Get-Changes-All
- DS-Replication-Get-Changes-In-Filtered-Set

Flags non-standard principals that have these rights.

.EXAMPLE
.\Test-ADDCSyncRights.ps1
#>

[CmdletBinding()]
param(
    [ValidateRange(1,200)]
    [int]$MaxSamples = 50
)

$ErrorActionPreference = 'Stop'

function New-Finding {
    param(
        [ValidateSet('Critical','High','Medium','Low','Info','Warning')]
        [string]$Severity,
        [string]$Category,
        [string]$Check,
        [string]$Message,
        [hashtable]$Data
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

try { Import-Module ActiveDirectory -ErrorAction Stop } catch {
    return New-Finding -Severity 'Warning' -Category 'Identity' -Check 'DCSync-Rights' `
        -Message 'ActiveDirectory module not available (RSAT required).' `
        -Data @{ Module = 'ActiveDirectory' }
}

# Replication right GUIDs
$guidGetChanges        = [Guid]'1131f6aa-9c07-11d1-f79f-00c04fc2dcd2'
$guidGetChangesAll     = [Guid]'1131f6ad-9c07-11d1-f79f-00c04fc2dcd2'
$guidGetChangesFiltSet = [Guid]'89e95b76-444d-4c62-991a-0facbeda640c'

$domainDn = (Get-ADDomain).DistinguishedName
$domainObj = Get-ADObject -Identity $domainDn -Properties nTSecurityDescriptor
$acl = $domainObj.nTSecurityDescriptor

# Principals commonly expected to have replication rights (environment-dependent; keep best-effort)
$expectedPatterns = @(
    'NT AUTHORITY\SYSTEM',
    'BUILTIN\Administrators',
    'Domain Admins',
    'Enterprise Admins'
)

$hits = New-Object System.Collections.Generic.List[object]

foreach ($ace in $acl.Access) {
    # We care about ExtendedRight / ControlAccess
    $isExt = ($ace.ActiveDirectoryRights.ToString() -match 'ExtendedRight|ControlAccess')
    if (-not $isExt) { continue }

    $objType = $ace.ObjectType
    if (-not $objType) { continue }

    if ($objType -in @($guidGetChanges, $guidGetChangesAll, $guidGetChangesFiltSet)) {
        $trustee = [string]$ace.IdentityReference
        $isExpected = $false
        foreach ($p in $expectedPatterns) {
            if ($trustee -like "*$p*") { $isExpected = $true; break }
        }

        $hits.Add([pscustomobject]@{
            Trustee     = $trustee
            RightGuid   = [string]$objType
            RightName   = switch ($objType) {
                $guidGetChanges        { 'DS-Replication-Get-Changes' }
                $guidGetChangesAll     { 'DS-Replication-Get-Changes-All' }
                $guidGetChangesFiltSet { 'DS-Replication-Get-Changes-In-Filtered-Set' }
                default { 'Unknown' }
            }
            AccessType  = [string]$ace.AccessControlType
            Inherited   = [bool]$ace.IsInherited
            Expected    = $isExpected
        }) | Out-Null
    }
}

$findings = New-Object System.Collections.Generic.List[object]

$findings.Add((New-Finding -Severity 'Info' -Category 'Identity' -Check 'DCSync-Rights-Summary' `
    -Message 'Evaluated domain root ACL for replication extended rights.' `
    -Data @{
        DomainDN = $domainDn
        TotalHits = $hits.Count
        UniqueTrustees = ($hits | Select-Object -ExpandProperty Trustee -Unique).Count
    })) | Out-Null

$nonExpected = $hits | Where-Object { $_.Expected -eq $false }
if ($nonExpected.Count -gt 0) {
    $sample = $nonExpected | Select-Object -First $MaxSamples Trustee, RightName, AccessType, Inherited
    $findings.Add((New-Finding -Severity 'High' -Category 'Identity' -Check 'DCSync-Rights-NonStandard' `
        -Message 'Non-standard principals with replication (DCSync-equivalent) rights detected on the domain root. Review immediately and validate change control.' `
        -Data @{ Count = $nonExpected.Count; Sample = $sample })) | Out-Null
}
else {
    $findings.Add((New-Finding -Severity 'Info' -Category 'Identity' -Check 'DCSync-Rights' `
        -Message 'No non-standard replication rights detected by this script (best-effort).' `
        -Data @{ TotalHits = $hits.Count })) | Out-Null
}

$findings
