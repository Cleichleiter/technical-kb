<#
.SYNOPSIS
Audits LDAP Signing and LDAP Channel Binding settings on all Domain Controllers.

.DESCRIPTION
Reads DC registry values via CIM (StdRegProv) for:
- LDAPServerIntegrity (LDAP signing requirement)
- LdapEnforceChannelBinding (LDAP channel binding enforcement)

Returns finding objects suitable for Invoke-ADSecurityAssessment.

NOTES
Registry locations:
HKLM\SYSTEM\CurrentControlSet\Services\NTDS\Parameters
- LDAPServerIntegrity (DWORD): 1=None, 2=Require
- LdapEnforceChannelBinding (DWORD): 0=Never, 1=When supported, 2=Always

.EXAMPLE
.\Test-ADLDAPSigningAndChannelBinding.ps1
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

    # StdRegProv: root keys
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
    return New-Finding -Severity 'Warning' -Category 'DCHardening' -Check 'LDAP-Signing-ChannelBinding' `
        -Message 'ActiveDirectory module not available. Run from a domain-joined admin workstation/server with RSAT.' `
        -Data @{ Module = 'ActiveDirectory' }
}

$dcList = @()
try { $dcList = Get-ADDomainController -Filter * | Sort-Object HostName } catch { $dcList = @() }

if (-not $dcList -or $dcList.Count -eq 0) {
    return New-Finding -Severity 'Warning' -Category 'DCHardening' -Check 'LDAP-Signing-ChannelBinding' `
        -Message 'No domain controllers discovered (or insufficient rights).' `
        -Data @{}
}

$subKey = 'SYSTEM\CurrentControlSet\Services\NTDS\Parameters'

$results = foreach ($dc in $dcList) {
    $name = $dc.HostName

    $ldapSigning = Get-RemoteRegDWORD -ComputerName $name -SubKey $subKey -ValueName 'LDAPServerIntegrity'
    $ldapCB      = Get-RemoteRegDWORD -ComputerName $name -SubKey $subKey -ValueName 'LdapEnforceChannelBinding'

    [pscustomobject]@{
        DomainController            = $name
        LDAPServerIntegrity         = $ldapSigning
        LDAPSigningMeaning          = switch ($ldapSigning) {
            2 { 'Require signing' }
            1 { 'None (not required)' }
            0 { 'Not set/unknown (treated as default)' }
            $null { 'Unreadable' }
            default { "Unknown ($ldapSigning)" }
        }
        LdapEnforceChannelBinding   = $ldapCB
        ChannelBindingMeaning       = switch ($ldapCB) {
            2 { 'Always' }
            1 { 'When supported' }
            0 { 'Never' }
            $null { 'Unreadable' }
            default { "Unknown ($ldapCB)" }
        }
    }
}

$findings = New-Object System.Collections.Generic.List[object]

# Summary
$findings.Add((New-Finding -Severity 'Info' -Category 'DCHardening' -Check 'LDAP-Signing-ChannelBinding-Summary' `
    -Message "Evaluated LDAP signing and channel binding on $($results.Count) DC(s)." `
    -Data @{ Results = $results })) | Out-Null

# Flag: LDAP signing not required
$notRequired = $results | Where-Object { $_.LDAPServerIntegrity -ne 2 }
if ($notRequired.Count -gt 0) {
    $sev = 'High'
    $sample = $notRequired | Select-Object -First 50 DomainController, LDAPServerIntegrity, LDAPSigningMeaning
    $findings.Add((New-Finding -Severity $sev -Category 'DCHardening' -Check 'LDAP-Signing-NotRequired' `
        -Message 'One or more DCs do not require LDAP signing. This increases exposure to LDAP relay/downgrade risks. Validate app compatibility and enforce LDAP signing.' `
        -Data @{ Count = $notRequired.Count; Sample = $sample })) | Out-Null
}

# Flag: Channel binding not enforced
$cbWeak = $results | Where-Object { $_.LdapEnforceChannelBinding -ne 2 }
if ($cbWeak.Count -gt 0) {
    $sev = 'Medium'
    $sample = $cbWeak | Select-Object -First 50 DomainController, LdapEnforceChannelBinding, ChannelBindingMeaning
    $findings.Add((New-Finding -Severity $sev -Category 'DCHardening' -Check 'LDAP-ChannelBinding-NotAlways' `
        -Message 'One or more DCs do not enforce LDAP channel binding as Always. Consider staged hardening to "When supported" then "Always" based on environment compatibility.' `
        -Data @{ Count = $cbWeak.Count; Sample = $sample })) | Out-Null
}

$findings
