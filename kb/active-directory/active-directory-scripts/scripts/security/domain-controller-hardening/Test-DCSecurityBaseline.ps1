<#
.SYNOPSIS
Performs a read-only baseline hardening check against common Domain Controller security settings.

.DESCRIPTION
Best-effort, configuration-focused checks via CIM registry reads:
- LDAP signing (LDAPServerIntegrity)
- LDAP channel binding (LdapEnforceChannelBinding)
- SMB1 disabled (LanmanServer\Parameters\SMB1)
- SMB signing (RequireSecuritySignature/EnableSecuritySignature)
- WDigest UseLogonCredential disabled
- LSA protection RunAsPPL enabled (where applicable)
- LmCompatibilityLevel strong

Outputs finding objects suitable for orchestration/reporting.

.EXAMPLE
.\Test-DCSecurityBaseline.ps1
#>

[CmdletBinding()]
param()

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

function Try-ImportAD {
    try { Import-Module ActiveDirectory -ErrorAction Stop; return $true } catch { return $false }
}

function Get-RemoteRegDWORD {
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][string]$SubKey,
        [Parameter(Mandatory)][string]$ValueName
    )

    $HKLM = 2147483650

    try {
        $reg = Get-CimInstance -ComputerName $ComputerName -Namespace root\cimv2 -ClassName StdRegProv -ErrorAction Stop
        $out = Invoke-CimMethod -InputObject $reg -MethodName GetDWORDValue -Arguments @{
            hDefKey     = $HKLM
            sSubKeyName = $SubKey
            sValueName  = $ValueName
        } -ErrorAction Stop

        if ($out.ReturnValue -ne 0) { return $null }
        return $out.uValue
    }
    catch {
        return $null
    }
}

if (-not (Try-ImportAD)) {
    return New-Finding -Severity 'Warning' -Category 'DCHardening' -Check 'DC-SecurityBaseline' `
        -Message 'ActiveDirectory module not available. Run from a domain-joined admin workstation/server with RSAT.' `
        -Data @{ Module = 'ActiveDirectory' }
}

$dcList = @()
try { $dcList = Get-ADDomainController -Filter * | Sort-Object HostName } catch { $dcList = @() }

if (-not $dcList -or $dcList.Count -eq 0) {
    return New-Finding -Severity 'Warning' -Category 'DCHardening' -Check 'DC-SecurityBaseline' `
        -Message 'No domain controllers discovered (or insufficient rights).' `
        -Data @{}
}

$ntdsKey = 'SYSTEM\CurrentControlSet\Services\NTDS\Parameters'
$lsaKey  = 'SYSTEM\CurrentControlSet\Control\Lsa'
$wdKey   = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest'
$srvKey  = 'SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'

$results = foreach ($dc in $dcList) {
    $name = $dc.HostName

    [pscustomobject]@{
        DomainController = $name

        LDAPServerIntegrity       = Get-RemoteRegDWORD -ComputerName $name -SubKey $ntdsKey -ValueName 'LDAPServerIntegrity'
        LdapEnforceChannelBinding = Get-RemoteRegDWORD -ComputerName $name -SubKey $ntdsKey -ValueName 'LdapEnforceChannelBinding'

        SMB1                      = Get-RemoteRegDWORD -ComputerName $name -SubKey $srvKey -ValueName 'SMB1'
        RequireSMBSigning         = Get-RemoteRegDWORD -ComputerName $name -SubKey $srvKey -ValueName 'RequireSecuritySignature'
        EnableSMBSigning          = Get-RemoteRegDWORD -ComputerName $name -SubKey $srvKey -ValueName 'EnableSecuritySignature'

        WDigestUseLogonCredential = Get-RemoteRegDWORD -ComputerName $name -SubKey $wdKey  -ValueName 'UseLogonCredential'
        RunAsPPL                  = Get-RemoteRegDWORD -ComputerName $name -SubKey $lsaKey -ValueName 'RunAsPPL'
        LmCompatibilityLevel      = Get-RemoteRegDWORD -ComputerName $name -SubKey $lsaKey -ValueName 'LmCompatibilityLevel'
    }
}

$findings = New-Object System.Collections.Generic.List[object]

$findings.Add((New-Finding -Severity 'Info' -Category 'DCHardening' -Check 'DC-SecurityBaseline-Summary' `
    -Message "Evaluated baseline settings on $($results.Count) DC(s)." `
    -Data @{ Results = $results })) | Out-Null

# Checks (baseline expectations are conservative and commonly recommended)
# LDAP signing required
$ldapWeak = $results | Where-Object { $_.LDAPServerIntegrity -ne 2 }
if ($ldapWeak.Count -gt 0) {
    $sample = $ldapWeak | Select-Object -First 50 DomainController, LDAPServerIntegrity
    $findings.Add((New-Finding -Severity 'High' -Category 'DCHardening' -Check 'Baseline-LDAPSigning' `
        -Message 'LDAP signing is not required on one or more DCs (or unreadable). Consider enforcing LDAP signing after compatibility review.' `
        -Data @{ Count = $ldapWeak.Count; Sample = $sample })) | Out-Null
}

# LDAP channel binding always
$cbWeak = $results | Where-Object { $_.LdapEnforceChannelBinding -ne 2 }
if ($cbWeak.Count -gt 0) {
    $sample = $cbWeak | Select-Object -First 50 DomainController, LdapEnforceChannelBinding
    $findings.Add((New-Finding -Severity 'Medium' -Category 'DCHardening' -Check 'Baseline-LDAPChannelBinding' `
        -Message 'LDAP channel binding is not set to Always on one or more DCs (or unreadable). Consider staged hardening.' `
        -Data @{ Count = $cbWeak.Count; Sample = $sample })) | Out-Null
}

# SMB1 disabled (SMB1 should be 0 or not present depending on OS; treat 1 as high risk)
$smb1On = $results | Where-Object { $_.SMB1 -eq 1 }
if ($smb1On.Count -gt 0) {
    $sample = $smb1On | Select-Object -First 50 DomainController, SMB1
    $findings.Add((New-Finding -Severity 'High' -Category 'DCHardening' -Check 'Baseline-SMB1' `
        -Message 'SMB1 appears enabled on one or more DCs. Disable SMB1 to reduce legacy protocol risk.' `
        -Data @{ Count = $smb1On.Count; Sample = $sample })) | Out-Null
}

# SMB signing required
$smbSignWeak = $results | Where-Object { $_.RequireSMBSigning -ne 1 }
if ($smbSignWeak.Count -gt 0) {
    $sample = $smbSignWeak | Select-Object -First 50 DomainController, RequireSMBSigning, EnableSMBSigning
    $findings.Add((New-Finding -Severity 'Medium' -Category 'DCHardening' -Check 'Baseline-SMBSigning' `
        -Message 'SMB signing does not appear to be required on one or more DCs (or unreadable). Require SMB signing where feasible.' `
        -Data @{ Count = $smbSignWeak.Count; Sample = $sample })) | Out-Null
}

# WDigest UseLogonCredential should be 0 (or not present on newer OS). 1 is a concern.
$wdigestOn = $results | Where-Object { $_.WDigestUseLogonCredential -eq 1 }
if ($wdigestOn.Count -gt 0) {
    $sample = $wdigestOn | Select-Object -First 50 DomainController, WDigestUseLogonCredential
    $findings.Add((New-Finding -Severity 'High' -Category 'DCHardening' -Check 'Baseline-WDigest' `
        -Message 'WDigest UseLogonCredential is enabled on one or more DCs. Disable to reduce credential exposure.' `
        -Data @{ Count = $wdigestOn.Count; Sample = $sample })) | Out-Null
}

# LSA protection (RunAsPPL) - not always enabled; treat as medium improvement opportunity
$lsaOff = $results | Where-Object { $_.RunAsPPL -ne 1 }
if ($lsaOff.Count -gt 0) {
    $sample = $lsaOff | Select-Object -First 50 DomainController, RunAsPPL
    $findings.Add((New-Finding -Severity 'Low' -Category 'DCHardening' -Check 'Baseline-LSAProtection' `
        -Message 'LSA protection (RunAsPPL) is not enabled on one or more DCs (or unreadable). Consider enabling where supported and tested.' `
        -Data @{ Count = $lsaOff.Count; Sample = $sample })) | Out-Null
}

# NTLM posture
$lmWeak = $results | Where-Object { $_.LmCompatibilityLevel -lt 4 -or $null -eq $_.LmCompatibilityLevel }
if ($lmWeak.Count -gt 0) {
    $sample = $lmWeak | Select-Object -First 50 DomainController, LmCompatibilityLevel
    $findings.Add((New-Finding -Severity 'Medium' -Category 'DCHardening' -Check 'Baseline-LmCompatibilityLevel' `
        -Message 'LmCompatibilityLevel appears weak or unknown on one or more DCs. Prefer stronger NTLMv2-only posture where compatible.' `
        -Data @{ Count = $lmWeak.Count; Sample = $sample })) | Out-Null
}

# If nothing flagged (beyond summary)
if (($findings | Where-Object { $_.Check -like 'Baseline-*' }).Count -eq 0) {
    $findings.Add((New-Finding -Severity 'Info' -Category 'DCHardening' -Check 'DC-SecurityBaseline' `
        -Message 'No baseline deviations detected by this script (best-effort registry checks).' `
        -Data @{})) | Out-Null
}

$findings
