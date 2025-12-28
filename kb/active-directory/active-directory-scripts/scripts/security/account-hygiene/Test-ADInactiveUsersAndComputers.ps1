<#
.SYNOPSIS
Finds inactive AD users and computers based on LastLogonDate and flags risky cases.

.DESCRIPTION
- Requires ActiveDirectory module
- Reports inactive users/computers beyond thresholds
- Highlights high-risk cases:
  - Privileged users inactive
  - Enabled users with PasswordNeverExpires
  - Stale computer accounts (common lateral movement footholds)

OUTPUT
Returns finding objects (Severity/Category/Check/Message/Data) suitable for orchestrator.

.PARAMETER UserInactiveDays
Users inactive for >= this many days are flagged.

.PARAMETER ComputerInactiveDays
Computers inactive for >= this many days are flagged.

.PARAMETER SearchBase
Optional DN scope (e.g., "OU=Users,DC=contoso,DC=com").

.PARAMETER IncludeDisabled
If set, includes disabled accounts in analysis.

.PARAMETER MaxSamples
Max number of sample items to include per finding.

.EXAMPLE
.\Test-ADInactiveUsersAndComputers.ps1

.EXAMPLE
.\Test-ADInactiveUsersAndComputers.ps1 -UserInactiveDays 60 -ComputerInactiveDays 90 -SearchBase "DC=contoso,DC=com"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateRange(1,3650)]
    [int]$UserInactiveDays = 90,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1,3650)]
    [int]$ComputerInactiveDays = 90,

    [Parameter(Mandatory = $false)]
    [string]$SearchBase,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeDisabled,

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
    return New-Finding -Severity 'Warning' -Category 'AccountHygiene' -Check 'Test-ADInactiveUsersAndComputers' `
        -Message 'ActiveDirectory module not available. Run from a domain-joined admin workstation/server with RSAT.' `
        -Data @{ Module = 'ActiveDirectory' }
}

$now = Get-Date
$userCutoff = $now.AddDays(-$UserInactiveDays)
$compCutoff = $now.AddDays(-$ComputerInactiveDays)

# Identify privileged groups to flag (Tier 0-ish)
$privGroups = @(
    'Domain Admins','Enterprise Admins','Schema Admins','Administrators','Account Operators','Backup Operators',
    'Server Operators','Print Operators','DnsAdmins','Group Policy Creator Owners'
)

$privMemberDns = New-Object System.Collections.Generic.HashSet[string]
foreach ($g in $privGroups) {
    try {
        $grp = Get-ADGroup -Identity $g -ErrorAction Stop
        $members = Get-ADGroupMember -Identity $grp -Recursive -ErrorAction Stop | Where-Object { $_.objectClass -eq 'user' }
        foreach ($m in $members) { [void]$privMemberDns.Add($m.DistinguishedName) }
    } catch {
        # group might not exist or access denied - ignore silently
    }
}

# Users
$userProps = @('Enabled','LastLogonDate','PasswordNeverExpires','PasswordLastSet','whenCreated','SID','DistinguishedName','SamAccountName','UserPrincipalName')
$userFilter = if ($IncludeDisabled) { '*' } else { 'Enabled -eq $true' }

$userParams = @{
    Filter     = $userFilter
    Properties = $userProps
}
if ($SearchBase) { $userParams.SearchBase = $SearchBase }

$users = Get-ADUser @userParams

$inactiveUsers = $users | Where-Object {
    # If LastLogonDate is null, treat as inactive if older than cutoff based on whenCreated
    if ($null -eq $_.LastLogonDate) { $_.whenCreated -lt $userCutoff } else { $_.LastLogonDate -lt $userCutoff }
}

$inactivePrivUsers = $inactiveUsers | Where-Object { $privMemberDns.Contains($_.DistinguishedName) }
$inactivePNEUsers  = $inactiveUsers | Where-Object { $_.PasswordNeverExpires -eq $true -and $_.Enabled -eq $true }

# Computers
$compProps = @('Enabled','LastLogonDate','OperatingSystem','whenCreated','DistinguishedName','DNSHostName')
$compFilter = if ($IncludeDisabled) { '*' } else { 'Enabled -eq $true' }

$compParams = @{
    Filter     = $compFilter
    Properties = $compProps
}
if ($SearchBase) { $compParams.SearchBase = $SearchBase }

$computers = Get-ADComputer @compParams

$inactiveComputers = $computers | Where-Object {
    if ($null -eq $_.LastLogonDate) { $_.whenCreated -lt $compCutoff } else { $_.LastLogonDate -lt $compCutoff }
}

$findings = New-Object System.Collections.Generic.List[object]

# Summary
$findings.Add((New-Finding -Severity 'Info' -Category 'AccountHygiene' -Check 'Inactive-Summary' `
    -Message "Inactive objects (cutoffs: Users=$UserInactiveDays days, Computers=$ComputerInactiveDays days). UsersInactive=$($inactiveUsers.Count), ComputersInactive=$($inactiveComputers.Count)." `
    -Data @{
        UserInactiveDays      = $UserInactiveDays
        ComputerInactiveDays  = $ComputerInactiveDays
        UsersTotal            = $users.Count
        ComputersTotal        = $computers.Count
        UsersInactive         = $inactiveUsers.Count
        ComputersInactive     = $inactiveComputers.Count
        SearchBase            = $SearchBase
        IncludeDisabled       = [bool]$IncludeDisabled
    })) | Out-Null

if ($inactiveUsers.Count -gt 0) {
    $sample = $inactiveUsers |
        Sort-Object @{ Expression = { if ($_.LastLogonDate) { $_.LastLogonDate } else { $_.whenCreated } } } |
        Select-Object -First $MaxSamples SamAccountName, UserPrincipalName, Enabled, LastLogonDate, whenCreated, PasswordNeverExpires
    $findings.Add((New-Finding -Severity 'Medium' -Category 'AccountHygiene' -Check 'Inactive-Users' `
        -Message 'Inactive user accounts detected. Consider disabling, moving to a quarantine OU, or validating business need.' `
        -Data @{ Count = $inactiveUsers.Count; Sample = $sample })) | Out-Null
}

if ($inactivePrivUsers.Count -gt 0) {
    $sample = $inactivePrivUsers |
        Select-Object -First $MaxSamples SamAccountName, UserPrincipalName, Enabled, LastLogonDate, whenCreated
    $findings.Add((New-Finding -Severity 'High' -Category 'AccountHygiene' -Check 'Inactive-PrivilegedUsers' `
        -Message 'Inactive privileged user accounts detected (Tier-0 group membership). This is a high-risk condition. Validate ownership and disable if not required.' `
        -Data @{ Count = $inactivePrivUsers.Count; Sample = $sample; GroupsChecked = $privGroups })) | Out-Null
}

if ($inactivePNEUsers.Count -gt 0) {
    $sample = $inactivePNEUsers |
        Select-Object -First $MaxSamples SamAccountName, UserPrincipalName, Enabled, LastLogonDate, PasswordLastSet, PasswordNeverExpires
    $findings.Add((New-Finding -Severity 'High' -Category 'AccountHygiene' -Check 'Inactive-PasswordNeverExpires' `
        -Message 'Inactive enabled user accounts with PasswordNeverExpires detected. This commonly indicates long-lived access. Validate and remediate.' `
        -Data @{ Count = $inactivePNEUsers.Count; Sample = $sample })) | Out-Null
}

if ($inactiveComputers.Count -gt 0) {
    $sample = $inactiveComputers |
        Sort-Object @{ Expression = { if ($_.LastLogonDate) { $_.LastLogonDate } else { $_.whenCreated } } } |
        Select-Object -First $MaxSamples Name, DNSHostName, Enabled, OperatingSystem, LastLogonDate, whenCreated
    $sev = if ($inactiveComputers.Count -gt 200) { 'High' } else { 'Medium' }
    $findings.Add((New-Finding -Severity $sev -Category 'AccountHygiene' -Check 'Inactive-Computers' `
        -Message 'Inactive computer accounts detected. Stale computer objects can be abused; consider disabling or moving to a quarantine OU and validating ownership.' `
        -Data @{ Count = $inactiveComputers.Count; Sample = $sample })) | Out-Null
}

$findings
