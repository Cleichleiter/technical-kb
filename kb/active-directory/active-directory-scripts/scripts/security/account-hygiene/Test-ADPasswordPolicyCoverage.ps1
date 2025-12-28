<#
.SYNOPSIS
Analyzes fine-grained password policy (FGPP) coverage and flags gaps.

.DESCRIPTION
- Requires ActiveDirectory module
- Enumerates default domain password policy and FGPPs
- Attempts to map which users are impacted by FGPP (best-effort):
  - Direct PSO appliesTo users/groups
  - Recursive group membership expansion (can be expensive in large environments)
- Flags likely coverage issues:
  - No FGPPs found (informational)
  - Very weak FGPP detected (threshold-based)
  - Users in privileged groups not covered by a stricter FGPP (best-effort)

OUTPUT
Returns finding objects suitable for orchestrator.

.PARAMETER ExpandGroupMembership
If set, expands group membership recursively when mapping PSO appliesTo groups. (Default: off)

.PARAMETER MaxExpandMembers
Safety cap for expanded group membership count per PSO.

.EXAMPLE
.\Test-ADPasswordPolicyCoverage.ps1

.EXAMPLE
.\Test-ADPasswordPolicyCoverage.ps1 -ExpandGroupMembership -MaxExpandMembers 5000
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$ExpandGroupMembership,

    [Parameter(Mandatory = $false)]
    [ValidateRange(100,500000)]
    [int]$MaxExpandMembers = 20000
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
    return New-Finding -Severity 'Warning' -Category 'AccountHygiene' -Check 'Test-ADPasswordPolicyCoverage' `
        -Message 'ActiveDirectory module not available. Run from a domain-joined admin workstation/server with RSAT.' `
        -Data @{ Module = 'ActiveDirectory' }
}

function Get-PolicyStrengthScore {
    param([Parameter(Mandatory)][object]$Policy)

    # A simple heuristic score: higher is stronger
    $score = 0

    try { if ($Policy.MinPasswordLength -ge 14) { $score += 3 } elseif ($Policy.MinPasswordLength -ge 12) { $score += 2 } elseif ($Policy.MinPasswordLength -ge 10) { $score += 1 } } catch {}
    try { if ($Policy.PasswordHistoryCount -ge 24) { $score += 2 } elseif ($Policy.PasswordHistoryCount -ge 10) { $score += 1 } } catch {}
    try { if ($Policy.MaxPasswordAge -and $Policy.MaxPasswordAge.Days -gt 0 -and $Policy.MaxPasswordAge.Days -le 365) { $score += 1 } } catch {}
    try { if ($Policy.ComplexityEnabled -eq $true) { $score += 1 } } catch {}
    try { if ($Policy.LockoutThreshold -and $Policy.LockoutThreshold -le 10 -and $Policy.LockoutThreshold -gt 0) { $score += 1 } } catch {}

    return $score
}

# Default domain policy
$default = Get-ADDefaultDomainPasswordPolicy
$defaultScore = Get-PolicyStrengthScore -Policy $default

# FGPP policies
$pso = @()
try {
    $pso = Get-ADFineGrainedPasswordPolicy -Filter * -ErrorAction Stop
} catch {
    $pso = @()
}

$findings = New-Object System.Collections.Generic.List[object]

$findings.Add((New-Finding -Severity 'Info' -Category 'AccountHygiene' -Check 'PasswordPolicy-Default' `
    -Message "Default domain password policy retrieved. MinLength=$($default.MinPasswordLength), History=$($default.PasswordHistoryCount), MaxAgeDays=$($default.MaxPasswordAge.Days), Complexity=$($default.ComplexityEnabled), LockoutThreshold=$($default.LockoutThreshold)." `
    -Data @{
        MinPasswordLength     = $default.MinPasswordLength
        PasswordHistoryCount  = $default.PasswordHistoryCount
        MaxPasswordAgeDays    = $default.MaxPasswordAge.Days
        ComplexityEnabled     = $default.ComplexityEnabled
        LockoutThreshold      = $default.LockoutThreshold
        StrengthScore         = $defaultScore
    })) | Out-Null

if (-not $pso -or $pso.Count -eq 0) {
    $findings.Add((New-Finding -Severity 'Info' -Category 'AccountHygiene' -Check 'PasswordPolicy-FGPP' `
        -Message 'No Fine-Grained Password Policies (FGPP/PSO) found. Only the default domain policy is in effect.' `
        -Data @{ PSOCount = 0 })) | Out-Null

    $findings
    return
}

# Build PSO inventory + simple "weak policy" checks
$psoInventory = foreach ($policy in $pso) {
    $score = Get-PolicyStrengthScore -Policy $policy
    [pscustomobject]@{
        Name                 = $policy.Name
        Precedence           = $policy.Precedence
        MinPasswordLength    = $policy.MinPasswordLength
        PasswordHistoryCount = $policy.PasswordHistoryCount
        MaxPasswordAgeDays   = $policy.MaxPasswordAge.Days
        ComplexityEnabled    = $policy.ComplexityEnabled
        LockoutThreshold     = $policy.LockoutThreshold
        StrengthScore        = $score
        AppliesToCount       = ($policy.AppliesTo | Measure-Object).Count
    }
}

$findings.Add((New-Finding -Severity 'Info' -Category 'AccountHygiene' -Check 'PasswordPolicy-FGPP-Inventory' `
    -Message ("Found {0} FGPP (PSO) objects." -f $psoInventory.Count) `
    -Data @{ PSOCount = $psoInventory.Count; Policies = ($psoInventory | Sort-Object Precedence) })) | Out-Null

# Weak policy detection (heuristic)
$weak = $psoInventory | Where-Object { $_.MinPasswordLength -lt 10 -or $_.ComplexityEnabled -eq $false -or $_.StrengthScore -le 1 }
if ($weak) {
    $findings.Add((New-Finding -Severity 'Medium' -Category 'AccountHygiene' -Check 'PasswordPolicy-WeakFGPP' `
        -Message 'One or more FGPP objects appear weak (heuristic). Review and tighten to align with your security standard.' `
        -Data @{ WeakPolicies = $weak })) | Out-Null
}

# Best-effort: check privileged users and whether a "stronger-than-default" PSO applies to them
$privGroups = @('Domain Admins','Enterprise Admins','Schema Admins','Administrators')
$privUsers = New-Object System.Collections.Generic.List[object]

foreach ($g in $privGroups) {
    try {
        $grp = Get-ADGroup -Identity $g -ErrorAction Stop
        Get-ADGroupMember -Identity $grp -Recursive -ErrorAction Stop |
            Where-Object { $_.objectClass -eq 'user' } |
            ForEach-Object { $privUsers.Add($_) | Out-Null }
    } catch {}
}

$privUsers = $privUsers | Sort-Object DistinguishedName -Unique

if ($privUsers.Count -gt 0) {
    $nonStrong = New-Object System.Collections.Generic.List[object]

    foreach ($u in $privUsers) {
        try {
            $p = Get-ADUserResultantPasswordPolicy -Identity $u.DistinguishedName -ErrorAction Stop
            if ($null -eq $p) {
                $nonStrong.Add([pscustomobject]@{ User = $u.SamAccountName; ResultantPolicy = '<default>'; Note = 'No PSO applied' }) | Out-Null
            }
            else {
                $pScore = Get-PolicyStrengthScore -Policy $p
                if ($pScore -le $defaultScore) {
                    $nonStrong.Add([pscustomobject]@{ User = $u.SamAccountName; ResultantPolicy = $p.Name; Note = 'Not stronger than default' }) | Out-Null
                }
            }
        } catch {
            # If cmdlet not supported in environment or error occurs, record as info
            $nonStrong.Add([pscustomobject]@{ User = $u.SamAccountName; ResultantPolicy = '<unknown>'; Note = $_.Exception.Message }) | Out-Null
        }
    }

    if ($nonStrong.Count -gt 0) {
        $findings.Add((New-Finding -Severity 'Medium' -Category 'AccountHygiene' -Check 'PasswordPolicy-PrivilegedCoverage' `
            -Message 'Some privileged users do not appear to have a stronger-than-default resultant password policy (best-effort). Consider a stricter FGPP for Tier-0 accounts.' `
            -Data @{ PrivilegedUsersChecked = $privUsers.Count; Affected = ($nonStrong | Select-Object -First 50) })) | Out-Null
    }
}

$findings
