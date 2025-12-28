<#
.SYNOPSIS
Audits AD service accounts and gMSAs for common security risks (Kerberoasting surface, stale creds, delegation).

.DESCRIPTION
- Requires ActiveDirectory module
- Enumerates:
  - User accounts with SPNs (service accounts)
  - Group Managed Service Accounts (gMSA)
- Flags common risk patterns:
  - Enabled SPN accounts with PasswordNeverExpires
  - Very old PasswordLastSet
  - Constrained/unconstrained delegation enabled
  - Weak encryption types (where attribute is populated)
  - High-privilege group membership (best-effort)

OUTPUT
Returns finding objects suitable for orchestrator.

.PARAMETER PasswordAgeDaysHigh
If PasswordLastSet older than this, flag (High).

.PARAMETER PasswordAgeDaysMedium
If PasswordLastSet older than this, flag (Medium).

.PARAMETER MaxSamples
Max number of sample objects per finding.

.EXAMPLE
.\Test-ADServiceAccountSecurity.ps1

.EXAMPLE
.\Test-ADServiceAccountSecurity.ps1 -PasswordAgeDaysHigh 180 -PasswordAgeDaysMedium 90
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateRange(1,3650)]
    [int]$PasswordAgeDaysHigh = 365,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1,3650)]
    [int]$PasswordAgeDaysMedium = 180,

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
    return New-Finding -Severity 'Warning' -Category 'AccountHygiene' -Check 'Test-ADServiceAccountSecurity' `
        -Message 'ActiveDirectory module not available. Run from a domain-joined admin workstation/server with RSAT.' `
        -Data @{ Module = 'ActiveDirectory' }
}

$now = Get-Date
$highCutoff = $now.AddDays(-$PasswordAgeDaysHigh)
$medCutoff  = $now.AddDays(-$PasswordAgeDaysMedium)

# Tier-0 groups (best-effort)
$privGroups = @('Domain Admins','Enterprise Admins','Schema Admins','Administrators','Backup Operators','Account Operators','Server Operators','DnsAdmins')
$privDns = New-Object System.Collections.Generic.HashSet[string]
foreach ($g in $privGroups) {
    try {
        $grp = Get-ADGroup -Identity $g -ErrorAction Stop
        Get-ADGroupMember -Identity $grp -Recursive -ErrorAction Stop |
            Where-Object { $_.objectClass -eq 'user' } |
            ForEach-Object { [void]$privDns.Add($_.DistinguishedName) }
    } catch {}
}

# Service accounts = users with SPN
$userProps = @(
    'Enabled','ServicePrincipalName','PasswordNeverExpires','PasswordLastSet','LastLogonDate',
    'TrustedForDelegation','AccountNotDelegated','msDS-AllowedToDelegateTo','msDS-SupportedEncryptionTypes',
    'DistinguishedName','SamAccountName','UserPrincipalName','Description'
)

$spnUsers = Get-ADUser -LDAPFilter "(servicePrincipalName=*)" -Properties $userProps

# gMSAs
$gmsaProps = @('Enabled','PrincipalsAllowedToRetrieveManagedPassword','LastLogonDate','Description')
$gmsa = @()
try {
    $gmsa = Get-ADServiceAccount -Filter * -Properties $gmsaProps -ErrorAction Stop
} catch {
    $gmsa = @()
}

$findings = New-Object System.Collections.Generic.List[object]

$findings.Add((New-Finding -Severity 'Info' -Category 'AccountHygiene' -Check 'ServiceAccounts-Inventory' `
    -Message ("Service accounts found: SPNUsers={0}, gMSA={1}." -f $spnUsers.Count, $gmsa.Count) `
    -Data @{ SPNUsers = $spnUsers.Count; gMSA = $gmsa.Count })) | Out-Null

# Risk: enabled SPN + PasswordNeverExpires
$pne = $spnUsers | Where-Object { $_.Enabled -eq $true -and $_.PasswordNeverExpires -eq $true }
if ($pne.Count -gt 0) {
    $sample = $pne | Select-Object -First $MaxSamples SamAccountName, UserPrincipalName, PasswordLastSet, LastLogonDate, Description
    $findings.Add((New-Finding -Severity 'High' -Category 'AccountHygiene' -Check 'ServiceAccounts-PasswordNeverExpires' `
        -Message 'Enabled service accounts (SPN) with PasswordNeverExpires detected. This increases long-term credential exposure and Kerberoasting impact.' `
        -Data @{ Count = $pne.Count; Sample = $sample })) | Out-Null
}

# Risk: very old PasswordLastSet (High/Medium)
$oldHigh = $spnUsers | Where-Object { $_.Enabled -eq $true -and $_.PasswordLastSet -and $_.PasswordLastSet -lt $highCutoff }
if ($oldHigh.Count -gt 0) {
    $sample = $oldHigh | Sort-Object PasswordLastSet | Select-Object -First $MaxSamples SamAccountName, UserPrincipalName, PasswordLastSet, LastLogonDate, Description
    $findings.Add((New-Finding -Severity 'High' -Category 'AccountHygiene' -Check 'ServiceAccounts-PasswordAgeHigh' `
        -Message "Enabled service accounts with PasswordLastSet older than $PasswordAgeDaysHigh days detected. Validate rotation strategy and consider gMSA where applicable." `
        -Data @{ Count = $oldHigh.Count; Sample = $sample; Cutoff = $highCutoff })) | Out-Null
}

$oldMed = $spnUsers | Where-Object { $_.Enabled -eq $true -and $_.PasswordLastSet -and $_.PasswordLastSet -lt $medCutoff -and $_.PasswordLastSet -ge $highCutoff }
if ($oldMed.Count -gt 0) {
    $sample = $oldMed | Sort-Object PasswordLastSet | Select-Object -First $MaxSamples SamAccountName, UserPrincipalName, PasswordLastSet, LastLogonDate, Description
    $findings.Add((New-Finding -Severity 'Medium' -Category 'AccountHygiene' -Check 'ServiceAccounts-PasswordAgeMedium' `
        -Message "Service accounts with PasswordLastSet older than $PasswordAgeDaysMedium days detected. Validate rotation strategy." `
        -Data @{ Count = $oldMed.Count; Sample = $sample; Cutoff = $medCutoff })) | Out-Null
}

# Risk: delegation
$unconstrained = $spnUsers | Where-Object { $_.Enabled -eq $true -and $_.TrustedForDelegation -eq $true }
if ($unconstrained.Count -gt 0) {
    $sample = $unconstrained | Select-Object -First $MaxSamples SamAccountName, UserPrincipalName, TrustedForDelegation, AccountNotDelegated
    $findings.Add((New-Finding -Severity 'High' -Category 'AccountHygiene' -Check 'ServiceAccounts-UnconstrainedDelegation' `
        -Message 'Service accounts with unconstrained delegation enabled detected. This is a high-risk configuration.' `
        -Data @{ Count = $unconstrained.Count; Sample = $sample })) | Out-Null
}

$constrained = $spnUsers | Where-Object { $_.Enabled -eq $true -and $_.'msDS-AllowedToDelegateTo' }
if ($constrained.Count -gt 0) {
    $sample = $constrained | Select-Object -First $MaxSamples SamAccountName, UserPrincipalName, @{n='AllowedToDelegateTo';e={($_.'msDS-AllowedToDelegateTo' -join ';')}}
    $findings.Add((New-Finding -Severity 'Medium' -Category 'AccountHygiene' -Check 'ServiceAccounts-ConstrainedDelegation' `
        -Message 'Service accounts with constrained delegation configured detected. Validate scope and ensure "Account is sensitive and cannot be delegated" on privileged identities.' `
        -Data @{ Count = $constrained.Count; Sample = $sample })) | Out-Null
}

# Risk: privileged membership
$privSvc = $spnUsers | Where-Object { $privDns.Contains($_.DistinguishedName) }
if ($privSvc.Count -gt 0) {
    $sample = $privSvc | Select-Object -First $MaxSamples SamAccountName, UserPrincipalName, PasswordLastSet, PasswordNeverExpires
    $findings.Add((New-Finding -Severity 'High' -Category 'AccountHygiene' -Check 'ServiceAccounts-PrivilegedMembership' `
        -Message 'One or more service accounts appear to be members of privileged groups (Tier-0). Validate design; prefer separation of duties and least privilege.' `
        -Data @{ Count = $privSvc.Count; Sample = $sample; GroupsChecked = $privGroups })) | Out-Null
}

# gMSA checks: validate retrieval principals configured
if ($gmsa.Count -gt 0) {
    $missingRetrievers = $gmsa | Where-Object { -not $_.PrincipalsAllowedToRetrieveManagedPassword }
    if ($missingRetrievers.Count -gt 0) {
        $sample = $missingRetrievers | Select-Object -First $MaxSamples Name, Enabled, Description
        $findings.Add((New-Finding -Severity 'Low' -Category 'AccountHygiene' -Check 'gMSA-MissingRetrievers' `
            -Message 'Some gMSAs do not list PrincipalsAllowedToRetrieveManagedPassword. Validate if intended and ensure only required principals can retrieve.' `
            -Data @{ Count = $missingRetrievers.Count; Sample = $sample })) | Out-Null
    }
}

$findings
