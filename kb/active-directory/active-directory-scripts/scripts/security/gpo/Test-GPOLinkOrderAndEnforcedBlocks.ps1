<#
.SYNOPSIS
Audits GPO link order, enforced links, and Block Inheritance usage across the domain.

.DESCRIPTION
Flags:
- OUs/domains with Block Inheritance enabled (review required)
- Enforced links (No Override) which can bypass inheritance expectations
- Suspicious combinations (Enforced + Block Inheritance in same subtree)

Requires GroupPolicy module.

OUTPUT
Finding objects.

.EXAMPLE
.\Test-GPOLinkOrderAndEnforcedBlocks.ps1
#>

[CmdletBinding()]
param(
    [ValidateRange(1,5000)]
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

try {
    Import-Module GroupPolicy -ErrorAction Stop
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    return New-Finding -Severity 'Warning' -Category 'GPO' -Check 'GPO-LinkOrder-Enforcement' `
        -Message 'Required modules not available (GroupPolicy + ActiveDirectory).' `
        -Data @{ Needed = @('GroupPolicy','ActiveDirectory') }
}

$domainDn = (Get-ADDomain).DistinguishedName

# Collect domain + OU targets
$targets = New-Object System.Collections.Generic.List[string]
$targets.Add($domainDn) | Out-Null

Get-ADOrganizationalUnit -Filter * -Properties DistinguishedName |
    ForEach-Object { $targets.Add($_.DistinguishedName) | Out-Nu_
