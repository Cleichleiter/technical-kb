<#
.SYNOPSIS
Audits Kerberos delegation configurations in Active Directory and flags common risk patterns.

.DESCRIPTION
Read-only assessment that identifies:
- Unconstrained delegation (TrustedForDelegation) on computers/users
- Constrained delegation (msDS-AllowedToDelegateTo) on computers/users
- Resource-based constrained delegation (msDS-AllowedToActOnBehalfOfOtherIdentity) on computers
- Privileged accounts NOT marked "Account is sensitive and cannot be delegated"
- Privileged accounts that are delegatable (higher risk if delegation exists elsewhere)

This script is designed to return standardized finding objects compatible with Invoke-ADSecurityAssessment.

.PARAMETER SearchBase
Optional DN to scope the search (e.g., "OU=Servers,DC=contoso,DC=com").

.PARAMETER MaxSamples
Max number of sample objects to include per finding.

.EXAMPLE
.\Test-ADKerberosDelegationRisk.ps1

.EXAMPLE
.\Test-ADKerberosDelegationRisk.ps1 -SearchBase "OU=Servers,DC=contoso,DC=com" -MaxSamples 25
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SearchBase,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1,500)]
    [int]$MaxSamples = 50
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
    try { Import-Module ActiveDirectory -ErrorAction Stop; return $true } catch { return $false }
}

if (-not (Try-ImportAD)) {
    return New-Finding -Severity 'Warning' -Category 'Kerberos' -Check 'Kerberos-Delegation-Risk' `
        -Message 'ActiveDirectory module not available. Run from a domain-joined admin workstation/server with RSAT.' `
        -Data @{ Module = 'ActiveDirectory' }
}

# Tier-0 / privileged groups (best-effort)
$privGroups = @(
    'Domain Admins','Enterprise Admins','Schema Admins','Administrators',
    'Account Operators','Backup Operators','Server Operators','DnsAdmins',
    'Group Policy Creator Owners'
)

$privUserDns = New-Object System.Collections.Generic.HashSet[string]
foreach ($g in $privGroups) {
    try {
        $grp = Get-ADGroup -Identity $g -ErrorAction Stop
        Get-ADGroupMember -Identity $grp -Recursive -ErrorAction Stop |
            Where-Object { $_.objectClass -eq 'user' } |
            ForEach-Object { [void]$privUserDns.Add($_.DistinguishedName) }
    } catch {
        # Ignore groups that don't exist or can't be queried
    }
}

# Query properties
$userProps = @(
    'Enabled','SamAccountName','UserPrincipalName','DistinguishedName',
    'TrustedForDelegation','AccountNotDelegated','msDS-AllowedToDelegateTo','servicePrincipalName'
)

$compProps = @(
    'Enabled','Name','DNSHostName','DistinguishedName','OperatingSystem',
    'TrustedForDelegation','AccountNotDelegated','msDS-AllowedToDelegateTo','msDS-AllowedToActOnBehalfOfOtherIdentity'
)

$userParams = @{
    Filter     = '*'
    Properties = $userProps
}
$compParams = @{
    Filter     = '*'
    Properties = $compProps
}
if ($SearchBase) {
    $userParams.SearchBase = $SearchBase
    $compParams.SearchBase = $SearchBase
}

$users = Get-ADUser @userParams
$computers = Get-ADComputer @compParams

# Unconstrained delegation
$unconstrainedUsers = $users | Where-Object { $_.Enabled -eq $true -and $_.TrustedForDelegation -eq $true }
$unconstrainedComps = $computers | Where-Object { $_.Enabled -eq $true -and $_.TrustedForDelegation -eq $true }

# Constrained delegation
$constrainedUsers = $users | Where-Object { $_.Enabled -eq $true -and $_.'msDS-AllowedToDelegateTo' }
$constrainedComps = $computers | Where-Object { $_.Enabled -eq $true -and $_.'msDS-AllowedToDelegateTo' }

# Resource-based constrained delegation (RBCD)
$rbcdComps = $computers | Where-Object { $_.Enabled -eq $true -and $_.'msDS-AllowedToActOnBehalfOfOtherIdentity' }

# Privileged accounts not marked "Account is sensitive and cannot be delegated"
$privUsers = $users | Where-Object { $privUserDns.Contains($_.DistinguishedName) }
$privDelegatable = $privUsers | Where-Object { $_.Enabled -eq $true -and $_.AccountNotDelegated -ne $true }

# Identify privileged accounts that ALSO have SPNs (higher-impact if delegatable)
$privWithSpn = $privDelegatable | Where-Object { $_.servicePrincipalName }

$findings = New-Object System.Collections.Generic.List[object]

# Summary
$findings.Add((New-Finding -Severity 'Info' -Category 'Kerberos' -Check 'Kerberos-Delegation-Summary' `
    -Message ("Kerberos delegation inventory: Unconstrained(User={0},Computer={1}); Constrained(User={2},Computer={3}); RBCD(Computer={4}); PrivilegedDelegatable={5}." -f `
        $unconstrainedUsers.Count, $unconstrainedComps.Count, $constrainedUsers.Count, $constrainedComps.Count, $rbcdComps.Count, $privDelegatable.Count) `
    -Data @{
        SearchBase            = $SearchBase
        UnconstrainedUsers    = $unconstrainedUsers.Count
        UnconstrainedComputers= $unconstrainedComps.Count
        ConstrainedUsers      = $constrainedUsers.Count
        ConstrainedComputers  = $constrainedComps.Count
        RBCDComputers         = $rbcdComps.Count
        PrivilegedUsersFound  = $privUsers.Count
        PrivilegedDelegatable = $privDelegatable.Count
    })) | Out-Null

# Unconstrained delegation is typically high risk
if ($unconstrainedUsers.Count -gt 0) {
    $sample = $unconstrainedUsers | Select-Object -First $MaxSamples SamAccountName, UserPrincipalName, TrustedForDelegation, AccountNotDelegated
    $findings.Add((New-Finding -Severity 'High' -Category 'Kerberos' -Check 'Kerberos-UnconstrainedDelegation-Users' `
        -Message 'Enabled user accounts with unconstrained delegation detected. This is high risk. Validate need and remove where possible.' `
        -Data @{ Count = $unconstrainedUsers.Count; Sample = $sample })) | Out-Null
}

if ($unconstrainedComps.Count -gt 0) {
    $sample = $unconstrainedComps | Select-Object -First $MaxSamples Name, DNSHostName, OperatingSystem, TrustedForDelegation
    $findings.Add((New-Finding -Severity 'High' -Category 'Kerberos' -Check 'Kerberos-UnconstrainedDelegation-Computers' `
        -Message 'Enabled computer accounts with unconstrained delegation detected. This is high risk. Validate need and remove where possible.' `
        -Data @{ Count = $unconstrainedComps.Count; Sample = $sample })) | Out-Null
}

# Constrained delegation is medium risk (depends on scope)
if ($constrainedUsers.Count -gt 0) {
    $sample = $constrainedUsers | Select-Object -First $MaxSamples SamAccountName, UserPrincipalName, @{n='AllowedToDelegateTo';e={($_.'msDS-AllowedToDelegateTo' -join ';')}}
    $findings.Add((New-Finding -Severity 'Medium' -Category 'Kerberos' -Check 'Kerberos-ConstrainedDelegation-Users' `
        -Message 'Enabled user accounts with constrained delegation configured detected. Validate scope and ensure least privilege.' `
        -Data @{ Count = $constrainedUsers.Count; Sample = $sample })) | Out-Null
}

if ($constrainedComps.Count -gt 0) {
    $sample = $constrainedComps | Select-Object -First $MaxSamples Name, DNSHostName, @{n='AllowedToDelegateTo';e={($_.'msDS-AllowedToDelegateTo' -join ';')}}
    $findings.Add((New-Finding -Severity 'Medium' -Category 'Kerberos' -Check 'Kerberos-ConstrainedDelegation-Computers' `
        -Message 'Enabled computer accounts with constrained delegation configured detected. Validate scope and ensure least privilege.' `
        -Data @{ Count = $constrainedComps.Count; Sample = $sample })) | Out-Null
}

# RBCD can be legitimate but is commonly abused when permissions are weak
if ($rbcdComps.Count -gt 0) {
    $sample = $rbcdComps | Select-Object -First $MaxSamples Name, DNSHostName, OperatingSystem
    $findings.Add((New-Finding -Severity 'Medium' -Category 'Kerberos' -Check 'Kerberos-RBCD-Computers' `
        -Message 'Computers with Resource-Based Constrained Delegation (RBCD) configured detected. Validate who can modify the target object and document intent.' `
        -Data @{ Count = $rbcdComps.Count; Sample = $sample })) | Out-Null
}

# Privileged users should generally be "Account is sensitive and cannot be delegated"
if ($privDelegatable.Count -gt 0) {
    $sample = $privDelegatable | Select-Object -First $MaxSamples SamAccountName, UserPrincipalName, AccountNotDelegated
    $findings.Add((New-Finding -Severity 'High' -Category 'Kerberos' -Check 'Kerberos-PrivilegedDelegatable' `
        -Message 'Privileged users not marked as "Account is sensitive and cannot be delegated" detected. Marking these accounts as non-delegatable reduces delegation abuse impact.' `
        -Data @{ Count = $privDelegatable.Count; Sample = $sample; GroupsChecked = $privGroups })) | Out-Null
}

# Privileged + SPN + delegatable is particularly concerning
if ($privWithSpn.Count -gt 0) {
    $sample = $privWithSpn | Select-Object -First $MaxSamples SamAccountName, UserPrincipalName, @{n='SPNs';e={($_.servicePrincipalName -join ';')}}
    $findings.Add((New-Finding -Severity 'High' -Category 'Kerberos' -Check 'Kerberos-PrivilegedDelegatable-WithSPN' `
        -Message 'Privileged service accounts (SPN present) that are delegatable detected. This increases potential blast radius. Validate design and tighten controls.' `
        -Data @{ Count = $privWithSpn.Count; Sample = $sample })) | Out-Null
}

# If no relevant findings beyond summary
$nonSummary = $findings | Where-Object { $_.Check -notlike '*Summary*' }
if ($nonSummary.Count -eq 0) {
    $findings.Add((New-Finding -Severity 'Info' -Category 'Kerberos' -Check 'Kerberos-Delegation-Risk' `
        -Message 'No Kerberos delegation risks detected by this script (best-effort).' `
        -Data @{})) | Out-Null
}

$findings
