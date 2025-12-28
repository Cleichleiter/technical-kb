<#
.SYNOPSIS
Produces a decision report for FSMO seizure and prints suggested commands.

.DESCRIPTION
Use when a role holder is offline/unrecoverable and you suspect seizure is required.
This script will:
- Show current FSMO owners
- Test whether the current owner responds
- Provide printed steps/commands for seizure ONLY if owner is not reachable

It does NOT perform seizure automatically.

.PARAMETER TargetDC
DC that would receive seized roles (must be healthy, writable).

.PARAMETER Roles
Roles to consider for seizure: SchemaMaster, DomainNamingMaster, PDCEmulator, RIDMaster, InfrastructureMaster, All

.EXAMPLE
.\Seize-FSMORoles-DecisionGuide.ps1 -TargetDC DC02.contoso.com -Roles All
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TargetDC,
    [ValidateSet('SchemaMaster','DomainNamingMaster','PDCEmulator','RIDMaster','InfrastructureMaster','All')]
    [string[]]$Roles = @('All')
)

$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory -ErrorAction Stop

$forest = Get-ADForest
$domain = Get-ADDomain

$owners = [ordered]@{
    SchemaMaster         = $forest.SchemaMaster
    DomainNamingMaster   = $forest.DomainNamingMaster
    PDCEmulator          = $domain.PDCEmulator
    RIDMaster            = $domain.RIDMaster
    InfrastructureMaster = $domain.InfrastructureMaster
}

$selected = if ($Roles -contains 'All') { $owners.Keys } else { $Roles }

$target = Get-ADDomainController -Identity $TargetDC -ErrorAction Stop
if ($target.IsReadOnly) { throw "Target DC '$TargetDC' is an RODC. Seizure requires a writable DC." }

$checks = foreach ($r in $selected) {
    $owner = $owners[$r]
    $reachable = $false
    try { $reachable = Test-Connection -ComputerName $owner -Count 2 -Quiet -ErrorAction Stop } catch { $reachable = $false }

    [pscustomobject]@{
        Role        = $r
        CurrentOwner= $owner
        OwnerReachable = $reachable
        Recommendation = if ($reachable) { 'Do NOT seize. Transfer instead.' } else { 'Owner unreachable. Seizure may be required if unrecoverable.' }
    }
}

$checks

"`n--- Suggested commands (printed only; not executed) ---"
"`nTransfer (preferred) example:"
"Move-ADDirectoryServerOperationMasterRole -Identity `"$($target.HostName)`" -OperationMasterRole $($selected -join ',')"

"`nIf, and only if, the current owner is unrecoverable and you accept the AD cleanup steps:"
"Move-ADDirectoryServerOperationMasterRole -Identity `"$($target.HostName)`" -OperationMasterRole $($selected -join ',') -Force"
"`nPost-seizure: ensure you never bring the old owner back online without proper metadata cleanup/rebuild."
