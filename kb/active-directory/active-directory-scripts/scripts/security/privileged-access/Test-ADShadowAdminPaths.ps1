<#
.SYNOPSIS
Detects common "shadow admin" delegation paths via risky ACLs on Tier-0 objects.

.DESCRIPTION
Read-only best-effort ACL audit of:
- Domain root
- AdminSDHolder
- Privileged groups (Domain Admins, Enterprise Admins, Schema Admins, Administrators)
- OU=Domain Controllers (if present)

Flags non-standard principals granted high-impact rights:
- GenericAll, GenericWrite, WriteDacl, WriteOwner
- WriteProperty on "member" attribute (can grant ability to add members to groups)

NOTES
The "member" attribute GUID used here is commonly:
bf9679c0-0de6-11d0-a285-00aa003049e2

This script does not attempt graph analysis; it identifies dangerous delegations worth immediate review.

.EXAMPLE
.\Test-ADShadowAdminPaths.ps1
#>

[CmdletBinding()]
param(
    [ValidateRange(1,500)]
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
    return New-Finding -Severity 'Warning' -Category 'Identity' -Check 'ShadowAdmin-ACLs' `
        -Message 'ActiveDirectory module not available (RSAT required).' `
        -Data @{ Module = 'ActiveDirectory' }
}

$domain = Get-ADDomain
$domainDn = $domain.DistinguishedName

# Targets
$targets = New-Object System.Collections.Generic.List[object]
$targets.Add([pscustomobject]@{ Name='DomainRoot'; DN=$domainDn }) | Out-Null
$targets.Add([pscustomobject]@{ Name='AdminSDHolder'; DN="CN=AdminSDHolder,CN=System,$domainDn" }) | Out-Null

# Privileged groups
$privGroupNames = @('Domain Admins','Enterprise Admins','Schema Admins','Administrators')
foreach ($g in $privGroupNames) {
    try {
        $grp = Get-ADGroup -Identity $g -ErrorAction Stop
        $targets.Add([pscustomobject]@{ Name="Group:$($grp.Name)"; DN=$grp.DistinguishedName }) | Out-Null
    } catch { }
}

# OU=Domain Controllers
try {
    $dcOu = Get-ADOrganizationalUnit -LDAPFilter '(ou=Domain Controllers)' -SearchBase $domainDn -SearchScope Subtree -ErrorAction Stop |
        Select-Object -First 1
    if ($dcOu) {
        $targets.Add([pscustomobject]@{ Name='OU:Domain Controllers'; DN=$dcOu.DistinguishedName }) | Out-Null
    }
} catch { }

# Expected principals patterns (best-effort)
$expectedPatterns = @(
    'NT AUTHORITY\SYSTEM',
    'BUILTIN\Administrators',
    'Domain Admins',
    'Enterprise Admins',
    'Schema Admins',
    'Group Policy Creator Owners'
)

$memberAttrGuid = [Guid]'bf9679c0-0de6-11d0-a285-00aa003049e2' # member

$hits = New-Object System.Collections.Generic.List[object]

foreach ($t in $targets) {
    $obj = $null
    try {
        $obj = Get-ADObject -Identity $t.DN -Properties nTSecurityDescriptor -ErrorAction Stop
    } catch { continue }

    $acl = $obj.nTSecurityDescriptor
    foreach ($ace in $acl.Access) {
        $trustee = [string]$ace.IdentityReference
        $rights  = $ace.ActiveDirectoryRights

        $danger =
            ($rights.ToString() -match 'GenericAll|WriteDacl|WriteOwner|GenericWrite') -or
            ( ($rights.ToString() -match 'WriteProperty') -and ($ace.ObjectType -eq $memberAttrGuid) )

        if (-not $danger) { continue }

        $isExpected = $false
        foreach ($p in $expectedPatterns) {
            if ($trustee -like "*$p*") { $isExpected = $true; break }
        }

        $hits.Add([pscustomobject]@{
            Target     = $t.Name
            TargetDN   = $t.DN
            Trustee    = $trustee
            Rights     = $rights.ToString()
            ObjectType = if ($ace.ObjectType) { [string]$ace.ObjectType } else { $null }
            AccessType = [string]$ace.AccessControlType
            Inherited  = [bool]$ace.IsInherited
            Expected   = $isExpected
            RiskType   = if (($rights.ToString() -match 'WriteProperty') -and ($ace.ObjectType -eq $memberAttrGuid)) {
                'WriteProperty(member)'
            } else {
                'HighImpactRight'
            }
        }) | Out-Null
    }
}

$findings = New-Object System.Collections.Generic.List[object]

$findings.Add((New-Finding -Severity 'Info' -Category 'Identity' -Check 'ShadowAdmin-ACLs-Summary' `
    -Message 'Evaluated ACLs on Tier-0 objects for high-impact delegated rights.' `
    -Data @{
        TargetsEvaluated = $targets.Count
        TotalFindings    = $hits.Count
        UniqueTrustees   = ($hits | Select-Object -ExpandProperty Trustee -Unique).Count
    })) | Out-Null

$nonExpected = $hits | Where-Object { $_.Expected -eq $false }
if ($nonExpected.Count -gt 0) {
    $sample = $nonExpected | Select-Object -First $MaxSamples Target, Trustee, Rights, RiskType, Inherited
    $findings.Add((New-Finding -Severity 'High' -Category 'Identity' -Check 'ShadowAdmin-ACLs-NonStandard' `
        -Message 'Non-standard principals with high-impact rights on Tier-0 AD objects detected. This is a common shadow-admin path. Review and remediate with strict change control.' `
        -Data @{ Count = $nonExpected.Count; Sample = $sample })) | Out-Null
}
else {
    $findings.Add((New-Finding -Severity 'Info' -Category 'Identity' -Check 'ShadowAdmin-ACLs' `
        -Message 'No non-standard high-impact ACL delegations detected by this script (best-effort).' `
        -Data @{ TotalHits = $hits.Count })) | Out-Null
}

$findings
