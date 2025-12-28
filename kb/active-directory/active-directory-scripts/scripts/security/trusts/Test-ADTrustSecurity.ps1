<#
.SYNOPSIS
Audits Active Directory trust relationships and flags common security concerns.

.DESCRIPTION
Read-only checks:
- Enumerates trusts (direction, type, attributes, forest transitive)
- Flags external trusts and non-forest trusts for review (context-dependent)
- Flags trusts without SID filtering (where detectable)
- Flags trusts that allow unconstrained delegation across trusts (where detectable)
- Flags trusts with selective authentication disabled (where applicable)

NOTES
Trust security depends heavily on the business relationship. This script focuses on visibility and
basic guardrails rather than making absolute judgments.

.EXAMPLE
.\Test-ADTrustSecurity.ps1
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
    return New-Finding -Severity 'Warning' -Category 'Trusts' -Check 'AD-TrustSecurity' `
        -Message 'ActiveDirectory module not available (RSAT required).' `
        -Data @{ Module = 'ActiveDirectory' }
}

$trusts = @()
try {
    # In most environments, this will return all domain trusts
    $trusts = Get-ADTrust -Filter * -ErrorAction Stop
} catch {
    $trusts = @()
}

$findings = New-Object System.Collections.Generic.List[object]

if (-not $trusts -or $trusts.Count -eq 0) {
    $findings.Add((New-Finding -Severity 'Info' -Category 'Trusts' -Check 'AD-TrustSecurity' `
        -Message 'No trusts detected (or insufficient rights). If the environment uses trusts, run with appropriate privileges.' `
        -Data @{})) | Out-Null
    $findings
    return
}

# Build a normalized view
$inventory = $trusts | Select-Object `
    Name, TrustedDomain, TrustType, TrustDirection, ForestTransitive, SelectiveAuthentication, SIDFilteringForestAware, SIDFilteringQuarantined, UsesAESKeys, UsesRC4Encryption, TGTDelegation

$findings.Add((New-Finding -Severity 'Info' -Category 'Trusts' -Check 'AD-Trusts-Summary' `
    -Message "Enumerated $($trusts.Count) trust(s)." `
    -Data @{ Trusts = $inventory })) | Out-Null

# External trusts (often higher review priority)
$external = $trusts | Where-Object { $_.TrustType -eq 'External' }
if ($external.Count -gt 0) {
    $sample = $external | Select-Object -First $MaxSamples Name, TrustedDomain, TrustDirection, SelectiveAuthentication, SIDFilteringForestAware, SIDFilteringQuarantined
    $findings.Add((New-Finding -Severity 'Medium' -Category 'Trusts' -Check 'AD-Trusts-External' `
        -Message 'External trusts detected. Review necessity, boundary controls, SID filtering, and authentication scope.' `
        -Data @{ Count = $external.Count; Sample = $sample })) | Out-Null
}

# Trusts without selective authentication (context dependent; often desirable for strict boundaries)
$noSelective = $trusts | Where-Object { $_.SelectiveAuthentication -eq $false }
if ($noSelective.Count -gt 0) {
    $sample = $noSelective | Select-Object -First $MaxSamples Name, TrustedDomain, TrustType, TrustDirection, SelectiveAuthentication
    $findings.Add((New-Finding -Severity 'Low' -Category 'Trusts' -Check 'AD-Trusts-SelectiveAuth-Disabled' `
        -Message 'Selective Authentication is disabled on one or more trusts. For tighter boundary control, consider enabling Selective Authentication where appropriate.' `
        -Data @{ Count = $noSelective.Count; Sample = $sample })) | Out-Null
}

# SID filtering warnings (best-effort)
# SIDFilteringQuarantined = True usually indicates SID filtering applied for external trusts
$noSidFiltering = $trusts | Where-Object {
    ($_.TrustType -eq 'External') -and ($_.SIDFilteringQuarantined -eq $false)
}

if ($noSidFiltering.Count -gt 0) {
    $sample = $noSidFiltering | Select-Object -First $MaxSamples Name, TrustedDomain, TrustDirection, SIDFilteringQuarantined
    $findings.Add((New-Finding -Severity 'High' -Category 'Trusts' -Check 'AD-Trusts-SIDFiltering-Disabled' `
        -Message 'External trusts detected where SID filtering (quarantine) does not appear enabled. This can increase risk of SIDHistory abuse across the trust. Validate and remediate where appropriate.' `
        -Data @{ Count = $noSidFiltering.Count; Sample = $sample })) | Out-Null
}

# TGT delegation / delegation across trust (if available in your AD module version)
# If TGTDelegation is True, it can allow unconstrained delegation of TGT across trust (review carefully).
$tgtDel = $trusts | Where-Object { $_.PSObject.Properties.Name -contains 'TGTDelegation' -and $_.TGTDelegation -eq $true }
if ($tgtDel.Count -gt 0) {
    $sample = $tgtDel | Select-Object -First $MaxSamples Name, TrustedDomain, TrustType, TrustDirection, TGTDelegation
    $findings.Add((New-Finding -Severity 'High' -Category 'Trusts' -Check 'AD-Trusts-TGTDelegation' `
        -Message 'Trusts with TGT delegation enabled detected. Review carefully as this can broaden delegation impact across trust boundaries.' `
        -Data @{ Count = $tgtDel.Count; Sample = $sample })) | Out-Null
}

# Crypto signals (best-effort; fields may vary by environment)
$rc4Trusts = $trusts | Where-Object { $_.PSObject.Properties.Name -contains 'UsesRC4Encryption' -and $_.UsesRC4Encryption -eq $true }
if ($rc4Trusts.Count -gt 0) {
    $sample = $rc4Trusts | Select-Object -First $MaxSamples Name, TrustedDomain, TrustType, TrustDirection, UsesRC4Encryption, UsesAESKeys
    $findings.Add((New-Finding -Severity 'Low' -Category 'Trusts' -Check 'AD-Trusts-RC4' `
        -Message 'Trusts indicating RC4 encryption usage detected (best-effort signal). Review trust crypto posture and ensure modern encryption where feasible.' `
        -Data @{ Count = $rc4Trusts.Count; Sample = $sample })) | Out-Null
}

$findings
