<#
.SYNOPSIS
Shows the effective domain password requirements from a Domain Controller.

.DESCRIPTION
Collects:
- Default Domain Password Policy (Account Policy)
- Any Fine-Grained Password Policies (FGPP) and which groups/users they apply to
- The resultant password policy for a specific user (optional)

.NOTES
Run in an elevated PowerShell session on a DC (or a domain-joined admin workstation with RSAT).
#>

[CmdletBinding()]
param(
    # Optional: SamAccountName or UPN to calculate the resultant policy for a user
    [Parameter(Mandatory = $false)]
    [string]$User
)

function Assert-RunAsAdmin {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        throw "This script must be run from an elevated PowerShell session (Run as Administrator)."
    }
}

function Import-ADModule {
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        throw "ActiveDirectory module not found. Install RSAT or run on a Domain Controller."
    }
    Import-Module ActiveDirectory -ErrorAction Stop
}

function Show-DefaultDomainPasswordPolicy {
    Write-Host ""
    Write-Host "=== Default Domain Password Policy ==="
    $pol = Get-ADDefaultDomainPasswordPolicy

    [pscustomobject]@{
        Domain                          = $pol.DomainName
        MinPasswordLength               = $pol.MinPasswordLength
        PasswordHistoryCount            = $pol.PasswordHistoryCount
        MaxPasswordAge                  = $pol.MaxPasswordAge
        MinPasswordAge                  = $pol.MinPasswordAge
        ComplexityEnabled               = $pol.ComplexityEnabled
        ReversibleEncryptionEnabled     = $pol.ReversibleEncryptionEnabled
        LockoutThreshold                = $pol.LockoutThreshold
        LockoutDuration                 = $pol.LockoutDuration
        LockoutObservationWindow        = $pol.LockoutObservationWindow
    } | Format-List
}

function Show-FineGrainedPasswordPolicies {
    Write-Host ""
    Write-Host "=== Fine-Grained Password Policies (FGPP / PSOs) ==="

    $psos = Get-ADFineGrainedPasswordPolicy -Filter * -ErrorAction SilentlyContinue

    if (-not $psos) {
        Write-Host "No Fine-Grained Password Policies found in this domain."
        return
    }

    foreach ($pso in ($psos | Sort-Object Precedence, Name)) {
        Write-Host ""
        Write-Host ("--- {0} ---" -f $pso.Name)

        [pscustomobject]@{
            Name                          = $pso.Name
            Precedence                    = $pso.Precedence
            MinPasswordLength             = $pso.MinPasswordLength
            PasswordHistoryCount          = $pso.PasswordHistoryCount
            MaxPasswordAge                = $pso.MaxPasswordAge
            MinPasswordAge                = $pso.MinPasswordAge
            ComplexityEnabled             = $pso.ComplexityEnabled
            ReversibleEncryptionEnabled   = $pso.ReversibleEncryptionEnabled
            LockoutThreshold              = $pso.LockoutThreshold
            LockoutDuration               = $pso.LockoutDuration
            LockoutObservationWindow      = $pso.LockoutObservationWindow
        } | Format-List

        # Applied To: users/groups
        $applies = Get-ADFineGrainedPasswordPolicySubject -Identity $pso -ErrorAction SilentlyContinue
        if ($applies) {
            Write-Host "Applies To:"
            $applies | Select-Object Name, ObjectClass, DistinguishedName | Format-Table -AutoSize
        } else {
            Write-Host "Applies To: (no subjects returned)"
        }
    }
}

function Show-ResultantPolicyForUser {
    param([Parameter(Mandatory=$true)][string]$User)

    Write-Host ""
    Write-Host "=== Resultant Password Policy for User: $User ==="

    try {
        $u = Get-ADUser -Identity $User -ErrorAction Stop
    } catch {
        # Try UPN lookup if -Identity didn't work
        $u = Get-ADUser -Filter "UserPrincipalName -eq '$User'" -ErrorAction Stop
    }

    $rp = Get-ADUserResultantPasswordPolicy -Identity $u -ErrorAction SilentlyContinue

    if ($rp) {
        Write-Host "Resultant policy is a Fine-Grained Password Policy (PSO): $($rp.Name)"
        [pscustomobject]@{
            Name                          = $rp.Name
            Precedence                    = $rp.Precedence
            MinPasswordLength             = $rp.MinPasswordLength
            PasswordHistoryCount          = $rp.PasswordHistoryCount
            MaxPasswordAge                = $rp.MaxPasswordAge
            MinPasswordAge                = $rp.MinPasswordAge
            ComplexityEnabled             = $rp.ComplexityEnabled
            ReversibleEncryptionEnabled   = $rp.ReversibleEncryptionEnabled
            LockoutThreshold              = $rp.LockoutThreshold
            LockoutDuration               = $rp.LockoutDuration
            LockoutObservationWindow      = $rp.LockoutObservationWindow
        } | Format-List
    } else {
        Write-Host "No PSO applies to this user. Effective policy is the Default Domain Password Policy."
        # Show default policy again for convenience
        Show-DefaultDomainPasswordPolicy
    }
}

# Main
Assert-RunAsAdmin
Import-ADModule

Show-DefaultDomainPasswordPolicy
Show-FineGrainedPasswordPolicies

if ($User) {
    Show-ResultantPolicyForUser -User $User
}

Write-Host ""
Write-Host "Done."
