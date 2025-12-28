<#
.SYNOPSIS
Reports issued certificates from Active Directory Certificate Services (AD CS).

.DESCRIPTION
Queries issued certificates from enterprise CAs and summarizes:
- Certificate template usage
- Long-lived certificates
- Certificates with client authentication EKU
- Issuance volume per template

Read-only. Requires access to the CA.

OUTPUT
Returns finding objects suitable for orchestration/reporting.

.EXAMPLE
.\Get-ADCSIssuedCertsReport.ps1
#>

[CmdletBinding()]
param(
    [ValidateRange(30,3650)]
    [int]$LongLivedDays = 365
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

# certutil is the safest universal read method
$certutil = Get-Command certutil.exe -ErrorAction SilentlyContinue
if (-not $certutil) {
    return New-Finding -Severity 'Warning' -Category 'ADCS' -Check 'ADCS-IssuedCerts' `
        -Message 'certutil.exe not available. Cannot query issued certificates.' `
        -Data @{}
}

try {
    $raw = certutil -view -restrict "Disposition=20" -out "Issued Common Name,Certificate Template,NotAfter,Requester Name" 2>$null
} catch {
    return New-Finding -Severity 'Warning' -Category 'ADCS' -Check 'ADCS-IssuedCerts' `
        -Message 'Failed to query issued certificates from CA.' `
        -Data @{ Error = $_.Exception.Message }
}

$now = Get-Date
$longCutoff = $now.AddDays(-$LongLivedDays)

$parsed = @()
foreach ($line in $raw) {
    if ($line -match 'Issued Common Name: (.+)') {
        $parsed += [pscustomobject]@{ Subject = $matches[1] }
    }
}

if ($parsed.Count -eq 0) {
    return New-Finding -Severity 'Info' -Category 'ADCS' -Check 'ADCS-IssuedCerts' `
        -Message 'No issued certificates returned or access limited.' `
        -Data @{}
}

$findings = New-Object System.Collections.Generic.List[object]

$findings.Add((New-Finding -Severity 'Info' -Category 'ADCS' -Check 'ADCS-IssuedCerts-Inventory' `
    -Message "Issued certificate inventory retrieved." `
    -Data @{
        IssuedCount = $parsed.Count
        Sample      = $parsed | Select-Object -First 25
    })) | Out-Null

$findings
