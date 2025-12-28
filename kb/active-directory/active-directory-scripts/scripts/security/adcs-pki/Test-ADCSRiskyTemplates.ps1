<#
.SYNOPSIS
Identifies potentially risky Active Directory Certificate Services (AD CS) certificate templates.

.DESCRIPTION
Enumerates certificate templates from AD and flags common high-risk configurations:
- Client Authentication EKU
- Enroll rights granted to broad principals
- No manager approval required
- No authorized signatures required
- Templates usable for authentication by non-admins

This is a read-only assessment designed for security posture review.

OUTPUT
Returns finding objects compatible with Invoke-ADSecurityAssessment.

.EXAMPLE
.\Test-ADCSRiskyTemplates.ps1
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

# Ensure AD module
try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    return New-Finding -Severity 'Warning' -Category 'ADCS' -Check 'ADCS-Templates' `
        -Message 'ActiveDirectory module not available.' `
        -Data @{ Module = 'ActiveDirectory' }
}

# Locate template container
try {
    $configNC = (Get-ADRootDSE).configurationNamingContext
    $templateBase = "CN=Certificate Templates,CN=Public Key Services,CN=Services,$configNC"
    $templates = Get-ADObject -SearchBase $templateBase -LDAPFilter "(objectClass=pKICertificateTemplate)" `
        -Properties displayName, pKIExtendedKeyUsage, msPKI-Enrollment-Flag, msPKI-RA-Signature, nTSecurityDescriptor
} catch {
    return New-Finding -Severity 'Info' -Category 'ADCS' -Check 'ADCS-Templates' `
        -Message 'AD CS certificate templates not found. AD CS may not be deployed.' `
        -Data @{}
}

$findings = New-Object System.Collections.Generic.List[object]

foreach ($t in $templates) {
    $eku = $t.pKIExtendedKeyUsage
    $hasClientAuth = $eku -contains '1.3.6.1.5.5.7.3.2' # Client Authentication

    if (-not $hasClientAuth) { continue }

    $flags = $t.'msPKI-Enrollment-Flag'
    $sigReq = $t.'msPKI-RA-Signature'

    # Enrollment flags (bitwise)
    $requiresApproval = ($flags -band 0x2) -ne 0
    $noSecurityExt    = ($flags -band 0x20) -ne 0

    # ACL inspection (broad principals)
    $acl = $t.nTSecurityDescriptor
    $broadEnroll = $false

    foreach ($ace in $acl.Access) {
        if ($ace.IdentityReference -match 'Authenticated Users|Domain Users|Everyone') {
            if ($ace.ActiveDirectoryRights.ToString().Contains('ExtendedRight')) {
                $broadEnroll = $true
            }
        }
    }

    if ($broadEnroll -and -not $requiresApproval -and $sigReq -eq 0) {
        $findings.Add((New-Finding -Severity 'High' -Category 'ADCS' -Check 'ADCS-RiskyTemplate' `
            -Message "Certificate template '$($t.displayName)' allows client authentication with broad enrollment and no approval." `
            -Data @{
                Template        = $t.displayName
                ClientAuthEKU   = $true
                RequiresApproval= $requiresApproval
                SignatureCount  = $sigReq
                BroadEnrollment = $broadEnroll
            })) | Out-Null
    }
}

if ($findings.Count -eq 0) {
    $findings.Add((New-Finding -Severity 'Info' -Category 'ADCS' -Check 'ADCS-RiskyTemplate' `
        -Message 'No obviously risky AD CS certificate templates detected.' `
        -Data @{ TemplateCount = $templates.Count })) | Out-Null
}

$findings
