<#
.SYNOPSIS
Inventories privileged group membership and flags common review items (nested groups, disabled users, staleness).

.DESCRIPTION
Read-only:
- Enumerates key privileged groups and members (recursive)
- Flags nested groups within privileged groups (common escalation path)
- Flags disabled privileged users
- Flags privileged users with old lastLogonTimestamp (best-effort)

.PARAMETER InactiveDays
Days since lastLogonTimestamp considered "stale".

.PARAMETER MaxSamples
Max sample rows per finding.

.EXAMPLE
.\Test-ADPrivilegedGroupMembership.ps1
.EXAMPLE
.\Test-ADPrivilegedGroupMembership.ps1 -InactiveDays 90
#>

[CmdletBinding()]
param(
    [ValidateRange(1,3650)]
    [int]$InactiveDays = 180,

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
    return New-Finding -Severity 'Warning' -Category 'Identity' -Check 'Privileged-Groups' `
        -Message 'ActiveDirectory module not available (RSAT required).' `
        -Data @{ Module = 'ActiveDirectory' }
}

$groups = @(
    'Domain Admins','Enterprise Admins','Schema Admins','Administrators',
    'Account Operators','Backup Operators','Server Operators','DnsAdmins',
    'Group Policy Creator Owners','Protected Users'
)

$cutoff = (Get-Date).AddDays(-$InactiveDays)

$inventory = New-Object System.Collections.Generic.List[object]
$nestedGroups = New-Object System.Collections.Generic.List[object]
$disabledPrivUsers = New-Object System.Collections.Generic.List[object]
$stalePrivUsers = New-Object System.Collections.Generic.List[object]

foreach ($g in $groups) {
    $grp = $null
    try { $grp = Get-ADGroup -Identity $g -ErrorAction Stop } catch { continue }

    $members = @()
    try { $members = Get-ADGroupMember -Identity $grp -Recursive -ErrorAction Stop } catch { $members = @() }

    $inventory.Add([pscustomobject]@{
        GroupName   = $grp.Name
        GroupDN     = $grp.DistinguishedName
        MemberCount = $members.Count
        UserCount   = ($members | Where-Object { $_.objectClass -eq 'user' }).Count
        GroupCount  = ($members | Where-Object { $_.objectClass -eq 'group' }).Count
        ComputerCount = ($members | Where-Object { $_.objectClass -eq 'computer' }).Count
    }) | Out-Null

    foreach ($m in $members) {
        if ($m.objectClass -eq 'group') {
            $nestedGroups.Add([pscustomobject]@{
                PrivGroup = $grp.Name
                NestedGroup = $m.Name
                NestedGroupDN = $m.DistinguishedName
            }) | Out-Null
        }

        if ($m.objectClass -eq 'user') {
            try {
                $u = Get-ADUser -Identity $m.DistinguishedName -Properties Enabled,lastLogonTimestamp,SamAccountName,UserPrincipalName -ErrorAction Stop
                if ($u.Enabled -eq $false) {
                    $disabledPrivUsers.Add([pscustomobject]@{
                        PrivGroup = $grp.Name
                        SamAccountName = $u.SamAccountName
                        UPN = $u.UserPrincipalName
                    }) | Out-Null
                }

                if ($u.lastLogonTimestamp) {
                    $llt = [DateTime]::FromFileTimeUtc([Int64]$u.lastLogonTimestamp)
                    if ($llt -lt $cutoff) {
                        $stalePrivUsers.Add([pscustomobject]@{
                            PrivGroup = $grp.Name
                            SamAccountName = $u.SamAccountName
                            UPN = $u.UserPrincipalName
                            LastLogonTimestampUtc = $llt.ToString('s')
                        }) | Out-Null
                    }
                }
            } catch { }
        }
    }
}

$findings = New-Object System.Collections.Generic.List[object]

$findings.Add((New-Finding -Severity 'Info' -Category 'Identity' -Check 'Privileged-Groups-Summary' `
    -Message 'Collected privileged group membership summary.' `
    -Data @{ Inventory = $inventory })) | Out-Null

if ($nestedGroups.Count -gt 0) {
    $sample = $nestedGroups | Select-Object -First $MaxSamples PrivGroup, NestedGroup
    $findings.Add((New-Finding -Severity 'Medium' -Category 'Identity' -Check 'Privileged-Groups-NestedGroups' `
        -Message 'Nested groups detected inside privileged groups. This can expand blast radius and complicate audits. Review for least privilege.' `
        -Data @{ Count = $nestedGroups.Count; Sample = $sample })) | Out-Null
}

if ($disabledPrivUsers.Count -gt 0) {
    $sample = $disabledPrivUsers | Select-Object -First $MaxSamples PrivGroup, SamAccountName, UPN
    $findings.Add((New-Finding -Severity 'Low' -Category 'Identity' -Check 'Privileged-Groups-DisabledUsers' `
        -Message 'Disabled users found within privileged group membership. Confirm intent and remove if no longer required.' `
        -Data @{ Count = $disabledPrivUsers.Count; Sample = $sample })) | Out-Null
}

if ($stalePrivUsers.Count -gt 0) {
    $sample = $stalePrivUsers | Select-Object -First $MaxSamples PrivGroup, SamAccountName, LastLogonTimestampUtc
    $findings.Add((New-Finding -Severity 'Low' -Category 'Identity' -Check 'Privileged-Groups-StaleUsers' `
        -Message "Privileged users with old lastLogonTimestamp detected (>$InactiveDays days). Confirm accounts are still required and monitored." `
        -Data @{ Count = $stalePrivUsers.Count; Sample = $sample; InactiveDays = $InactiveDays })) | Out-Null
}

$findings
