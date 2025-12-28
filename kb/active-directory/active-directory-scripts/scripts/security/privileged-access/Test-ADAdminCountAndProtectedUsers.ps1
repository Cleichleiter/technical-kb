<#
.SYNOPSIS
Audits adminCount usage and Protected Users group coverage.

.DESCRIPTION
Read-only checks:
- Enabled users with adminCount=1 (AdminSDHolder protected) and whether they are still in privileged groups
  (stale adminCount can indicate historical privilege and lingering AdminSDHolder protection).
- Protected Users group membership and whether privileged users are included.

.PARAMETER MaxSamples
Maximum number of sample rows to include per finding.

.EXAMPLE
.\Test-ADAdminCountAndProtectedUsers.ps1
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
    return New-Finding -Severity 'Warning' -Category 'Identity' -Check 'AdminCount-ProtectedUsers' `
        -Message 'ActiveDirectory module not available (RSAT required).' `
        -Data @{ Module = 'ActiveDirectory' }
}

$privGroups = @(
    'Domain Admins','Enterprise Admins','Schema Admins','Administrators',
    'Account Operators','Backup Operators','Server Operators','DnsAdmins',
    'Group Policy Creator Owners'
)

# Build a set of privileged user DNs (best-effort)
$privUserDns = New-Object System.Collections.Generic.HashSet[string]
foreach ($g in $privGroups) {
    try {
        $grp = Get-ADGroup -Identity $g -ErrorAction Stop
        Get-ADGroupMember -Identity $grp -Recursive -ErrorAction Stop |
            Where-Object { $_.objectClass -eq 'user' } |
            ForEach-Object { [void]$privUserDns.Add($_.DistinguishedName) }
    } catch { }
}

# adminCount users
$adminCountUsers = Get-ADUser -LDAPFilter '(adminCount=1)' -Properties Enabled, adminCount, whenChanged, lastLogonTimestamp, memberOf, userAccountControl, samAccountName, userPrincipalName, distinguishedName
$enabledAdminCount = $adminCountUsers | Where-Object { $_.Enabled -eq $true }

# Stale adminCount: adminCount=1 but not in current privileged membership set
$staleAdminCount = $enabledAdminCount | Where-Object { -not $privUserDns.Contains($_.DistinguishedName) }

# Protected Users group
$protectedUsersGroup = $null
try { $protectedUsersGroup = Get-ADGroup -Identity 'Protected Users' -ErrorAction Stop } catch { }

$protectedMembers = @()
if ($protectedUsersGroup) {
    try {
        $protectedMembers = Get-ADGroupMember -Identity $protectedUsersGroup -Recursive -ErrorAction Stop
    } catch { $protectedMembers = @() }
}

$protectedMemberDns = New-Object System.Collections.Generic.HashSet[string]
$protectedMembers | Where-Object { $_.objectClass -eq 'user' } | ForEach-Object { [void]$protectedMemberDns.Add($_.DistinguishedName) }

# Privileged users missing from Protected Users
$privUsersMissingProtected = @()
if ($protectedUsersGroup) {
    $privUsersMissingProtected = $privUserDns | ForEach-Object { $_ } | Where-Object { -not $protectedMemberDns.Contains($_) }
}

# Non-privileged users in Protected Users (can be intentional, but review)
$nonPrivInProtected = @()
if ($protectedUsersGroup) {
    $nonPrivInProtected = $protectedMembers |
        Where-Object { $_.objectClass -eq 'user' -and -not $privUserDns.Contains($_.DistinguishedName) }
}

$findings = New-Object System.Collections.Generic.List[object]

$findings.Add((New-Finding -Severity 'Info' -Category 'Identity' -Check 'AdminCount-ProtectedUsers-Summary' `
    -Message "Evaluated adminCount and Protected Users coverage." `
    -Data @{
        AdminCountUsersTotal    = $adminCountUsers.Count
        AdminCountUsersEnabled  = $enabledAdminCount.Count
        StaleAdminCountEnabled  = $staleAdminCount.Count
        PrivilegedUsersCount    = $privUserDns.Count
        ProtectedUsersPresent   = [bool]$protectedUsersGroup
        ProtectedUsersMembers   = $protectedMembers.Count
    })) | Out-Null

if ($staleAdminCount.Count -gt 0) {
    $sample = $staleAdminCount | Select-Object -First $MaxSamples SamAccountName, UserPrincipalName, whenChanged, Enabled
    $findings.Add((New-Finding -Severity 'Medium' -Category 'Identity' -Check 'AdminCount-Stale' `
        -Message 'Enabled users with adminCount=1 that are not currently in common privileged groups detected. This often indicates historical privilege and lingering AdminSDHolder effects. Review and remediate where appropriate.' `
        -Data @{ Count = $staleAdminCount.Count; Sample = $sample })) | Out-Null
}

if (-not $protectedUsersGroup) {
    $findings.Add((New-Finding -Severity 'Low' -Category 'Identity' -Check 'ProtectedUsers-Missing' `
        -Message 'Protected Users group not found (domain functional level may be too low or feature not in use). Consider using Protected Users for highly privileged accounts where compatible.' `
        -Data @{})) | Out-Null
}
else {
    if ($privUsersMissingProtected.Count -gt 0) {
        $sampleDns = $privUsersMissingProtected | Select-Object -First $MaxSamples
        $sample = foreach ($dn in $sampleDns) {
            try { Get-ADUser -Identity $dn -Properties SamAccountName, UserPrincipalName, Enabled | Select-Object SamAccountName, UserPrincipalName, Enabled } catch { }
        }
        $findings.Add((New-Finding -Severity 'Low' -Category 'Identity' -Check 'ProtectedUsers-PrivilegedNotIncluded' `
            -Message 'Privileged users not in Protected Users detected. If compatible with your environment, adding Tier-0 accounts to Protected Users can reduce legacy auth exposure.' `
            -Data @{ Count = $privUsersMissingProtected.Count; Sample = ($sample | Select-Object -First $MaxSamples) })) | Out-Null
    }

    if ($nonPrivInProtected.Count -gt 0) {
        $sample = $nonPrivInProtected | Select-Object -First $MaxSamples Name, SamAccountName, DistinguishedName
        $findings.Add((New-Finding -Severity 'Info' -Category 'Identity' -Check 'ProtectedUsers-NonPrivilegedMembers' `
            -Message 'Non-privileged users found in Protected Users. This can be intentional, but should be documented because it can break legacy auth scenarios.' `
            -Data @{ Count = $nonPrivInProtected.Count; Sample = $sample })) | Out-Null
    }
}

$findings
