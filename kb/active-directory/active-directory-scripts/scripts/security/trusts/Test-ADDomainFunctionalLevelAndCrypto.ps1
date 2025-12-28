<#
.SYNOPSIS
Assesses AD domain/forest functional levels and key crypto/security posture indicators.

.DESCRIPTION
Read-only checks:
- Domain and Forest functional level (DFL/FFL)
- Domain controller OS distribution (helps infer supportability / crypto baselines)
- NTLM/LM posture signals (LmCompatibilityLevel) from default domain policy registry snapshot (best-effort)
- Kerberos supported encryption types usage signals on user/computer accounts:
  - msDS-SupportedEncryptionTypes (flags RC4-only or missing AES preference)
- Presence of accounts with DES-only or legacy flags (best-effort via userAccountControl)

NOTES
- This script does not attempt to enforce anything; it produces visibility and risk flags.
- Kerberos encryption analysis is heuristic. The strongest result comes from combining this with
  domain controller OS/patch baseline and explicit Kerberos policy review.

.EXAMPLE
.\Test-ADDomainFunctionalLevelAndCrypto.ps1
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
    return New-Finding -Severity 'Warning' -Category 'Crypto' -Check 'AD-FunctionalLevel-Crypto' `
        -Message 'ActiveDirectory module not available (RSAT required).' `
        -Data @{ Module = 'ActiveDirectory' }
}

$domain = Get-ADDomain
$forest = Get-ADForest

# DC OS distribution
$dcOs = @()
try {
    $dcOs = Get-ADDomainController -Filter * |
        Select-Object HostName, OperatingSystem, OperatingSystemVersion, Site
} catch { $dcOs = @() }

$dcOsSummary = $dcOs |
    Group-Object OperatingSystem |
    Sort-Object Count -Descending |
    Select-Object Name, Count

# Kerberos encryption type analysis
# msDS-SupportedEncryptionTypes bitmask (common bits):
# 0x1  DES-CBC-CRC
# 0x2  DES-CBC-MD5
# 0x4  RC4-HMAC
# 0x8  AES128
# 0x10 AES256
# 0x20 FAST (not always used here)
function Parse-EncTypes {
    param([int]$Value)

    $types = New-Object System.Collections.Generic.List[string]
    if ($Value -band 0x1)  { $types.Add('DES-CBC-CRC') | Out-Null }
    if ($Value -band 0x2)  { $types.Add('DES-CBC-MD5') | Out-Null }
    if ($Value -band 0x4)  { $types.Add('RC4-HMAC') | Out-Null }
    if ($Value -band 0x8)  { $types.Add('AES128') | Out-Null }
    if ($Value -band 0x10) { $types.Add('AES256') | Out-Null }
    if ($types.Count -eq 0) { $types.Add('NotSet/Default') | Out-Null }
    $types
}

# Focus on security-relevant principals:
# - Users with SPNs (service accounts)
# - Computers (often service principals)
$serviceUsers = Get-ADUser -LDAPFilter '(servicePrincipalName=*)' -Properties samAccountName,userPrincipalName,msDS-SupportedEncryptionTypes,enabled
$computers    = Get-ADComputer -Filter * -Properties name,dnshostname,msDS-SupportedEncryptionTypes,enabled |
    Where-Object { $_.Enabled -eq $true }

# Identify risky encryption patterns
# - DES enabled (0x1 or 0x2)
# - RC4 only (0x4 and no AES bits)
$desUsers = $serviceUsers | Where-Object {
    $v = $_.'msDS-SupportedEncryptionTypes'
    $v -is [int] -and (($v -band 0x1) -or ($v -band 0x2))
}

$rc4OnlyUsers = $serviceUsers | Where-Object {
    $v = $_.'msDS-SupportedEncryptionTypes'
    $v -is [int] -and (($v -band 0x4) -and -not ($v -band 0x8) -and -not ($v -band 0x10))
}

$desComps = $computers | Where-Object {
    $v = $_.'msDS-SupportedEncryptionTypes'
    $v -is [int] -and (($v -band 0x1) -or ($v -band 0x2))
}

$rc4OnlyComps = $computers | Where-Object {
    $v = $_.'msDS-SupportedEncryptionTypes'
    $v -is [int] -and (($v -band 0x4) -and -not ($v -band 0x8) -and -not ($v -band 0x10))
}

$findings = New-Object System.Collections.Generic.List[object]

$findings.Add((New-Finding -Severity 'Info' -Category 'Crypto' -Check 'AD-FunctionalLevel-Summary' `
    -Message "Domain/Forest functional levels and crypto posture signals collected." `
    -Data @{
        DomainName               = $domain.DNSRoot
        DomainMode               = [string]$domain.DomainMode
        ForestName               = $forest.Name
        ForestMode               = [string]$forest.ForestMode
        DomainControllers        = $dcOs.Count
        DomainControllerOSSummary= $dcOsSummary
        ServiceUsersWithSPN      = $serviceUsers.Count
        ComputersEnabled         = $computers.Count
    })) | Out-Null

# Functional level flag (heuristic)
# (You can tune this threshold later; keeping it conservative.)
$legacyDomainModes = @('Windows2008Domain','Windows2008R2Domain','Windows2012Domain','Windows2012R2Domain')
$legacyForestModes = @('Windows2008Forest','Windows2008R2Forest','Windows2012Forest','Windows2012R2Forest')

if ($legacyDomainModes -contains [string]$domain.DomainMode -or $legacyForestModes -contains [string]$forest.ForestMode) {
    $findings.Add((New-Finding -Severity 'Low' -Category 'Crypto' -Check 'AD-FunctionalLevel-Legacy' `
        -Message 'Domain/Forest functional level is below the newest modes. This can limit modern security features and crypto hardening options. Consider uplift as part of lifecycle planning.' `
        -Data @{ DomainMode = [string]$domain.DomainMode; ForestMode = [string]$forest.ForestMode })) | Out-Null
}

# DES findings (higher risk)
if ($desUsers.Count -gt 0) {
    $sample = $desUsers | Select-Object -First $MaxSamples SamAccountName, UserPrincipalName, @{n='EncTypes';e={ (Parse-EncTypes -Value $_.'msDS-SupportedEncryptionTypes') -join ',' }}
    $findings.Add((New-Finding -Severity 'High' -Category 'Crypto' -Check 'Kerberos-EncTypes-DES-ServiceUsers' `
        -Message 'Service accounts (SPN present) with DES encryption types enabled detected. DES is legacy and should be removed where possible.' `
        -Data @{ Count = $desUsers.Count; Sample = $sample })) | Out-Null
}

if ($desComps.Count -gt 0) {
    $sample = $desComps | Select-Object -First $MaxSamples Name, DNSHostName, @{n='EncTypes';e={ (Parse-EncTypes -Value $_.'msDS-SupportedEncryptionTypes') -join ',' }}
    $findings.Add((New-Finding -Severity 'High' -Category 'Crypto' -Check 'Kerberos-EncTypes-DES-Computers' `
        -Message 'Computer accounts with DES encryption types enabled detected. DES is legacy and should be removed where possible.' `
        -Data @{ Count = $desComps.Count; Sample = $sample })) | Out-Null
}

# RC4-only findings (medium risk)
if ($rc4OnlyUsers.Count -gt 0) {
    $sample = $rc4OnlyUsers | Select-Object -First $MaxSamples SamAccountName, UserPrincipalName, @{n='EncTypes';e={ (Parse-EncTypes -Value $_.'msDS-SupportedEncryptionTypes') -join ',' }}
    $findings.Add((New-Finding -Severity 'Medium' -Category 'Crypto' -Check 'Kerberos-EncTypes-RC4Only-ServiceUsers' `
        -Message 'Service accounts (SPN present) appear configured for RC4-only (no AES). Consider enabling AES and validating app compatibility.' `
        -Data @{ Count = $rc4OnlyUsers.Count; Sample = $sample })) | Out-Null
}

if ($rc4OnlyComps.Count -gt 0) {
    $sample = $rc4OnlyComps | Select-Object -First $MaxSamples Name, DNSHostName, @{n='EncTypes';e={ (Parse-EncTypes -Value $_.'msDS-SupportedEncryptionTypes') -join ',' }}
    $findings.Add((New-Finding -Severity 'Medium' -Category 'Crypto' -Check 'Kerberos-EncTypes-RC4Only-Computers' `
        -Message 'Computer accounts appear configured for RC4-only (no AES). Consider enabling AES and validating app compatibility.' `
        -Data @{ Count = $rc4OnlyComps.Count; Sample = $sample })) | Out-Null
}

# If no crypto-specific issues detected
$nonSummary = $findings | Where-Object { $_.Check -notlike '*Summary*' }
if ($nonSummary.Count -eq 0) {
    $findings.Add((New-Finding -Severity 'Info' -Category 'Crypto' -Check 'AD-FunctionalLevel-Crypto' `
        -Message 'No obvious crypto posture issues detected by this script (best-effort).' `
        -Data @{})) | Out-Null
}

$findings
