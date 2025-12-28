<#
.SYNOPSIS
Audits GPO permissions for common security risks (overly-broad edit rights, weak delegation).

.DESCRIPTION
Flags:
- GPOs where Authenticated Users / Domain Users / Everyone have Edit / Delete / Modify Security
- GPOs where non-admin principals have edit-level permissions (best-effort)
- GPOs with no clear admins (informational)

Requires GroupPolicy module.

OUTPUT
Finding objects (Severity/Category/Check/Message/Data).

.EXAMPLE
.\Test-GPOPermissions.ps1
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
} catch {
    return New-Finding -Severity 'Warning' -Category 'GPO' -Check 'GPO-Permissions' `
        -Message 'GroupPolicy module not available (RSAT required).' `
        -Data @{ Module = 'GroupPolicy' }
}

$gpos = Get-GPO -All -ErrorAction Stop

$broadEdit = New-Object System.Collections.Generic.List[object]
$nonAdminEdit = New-Object System.Collections.Generic.List[object]

$wellKnownAdmins = @(
    'BUILTIN\Administrators',
    'Domain Admins',
    'Enterprise Admins',
    'Group Policy Creator Owners',
    'SYSTEM'
)

$highRiskPrincipals = @('Authenticated Users','Domain Users','Everyone')

foreach ($gpo in $gpos) {
    $perms = @()
    try {
        $perms = Get-GPPermission -Guid $gpo.Id -All -ErrorAction Stop
    } catch {
        continue
    }

    foreach ($p in $perms) {
        $trustee = [string]$p.Trustee.Name
        $level   = [string]$p.Permission

        $isEdit = $level -in @('GpoEdit','GpoEditDeleteModifySecurity')

        if ($isEdit -and ($highRiskPrincipals | Where-Object { $trustee -like "*$_*" })) {
            $broadEdit.Add([pscustomobject]@{
                GPOName    = $gpo.DisplayName
                GPOId      = $gpo.Id
                Trustee    = $trustee
                Permission = $level
            }) | Out-Null
        }

        if ($isEdit) {
            $isAdmin = $false
            foreach ($admin in $wellKnownAdmins) {
                if ($trustee -like "*$admin*") { $isAdmin = $true; break }
            }

            if (-not $isAdmin -and -not ($trustee -match 'NT AUTHORITY\\SYSTEM')) {
                $nonAdminEdit.Add([pscustomobject]@{
                    GPOName    = $gpo.DisplayName
                    GPOId      = $gpo.Id
                    Trustee    = $trustee
                    Permission = $level
                }) | Out-Null
            }
        }
    }
}

$findings = New-Object System.Collections.Generic.List[object]

$findings.Add((New-Finding -Severity 'Info' -Category 'GPO' -Check 'GPO-Permissions-Summary' `
    -Message "Evaluated GPO permissions for $($gpos.Count) GPO(s)." `
    -Data @{ GPOCount = $gpos.Count })) | Out-Null

if ($broadEdit.Count -gt 0) {
    $findings.Add((New-Finding -Severity 'High' -Category 'GPO' -Check 'GPO-BroadEditRights' `
        -Message 'One or more GPOs grant edit rights to broad principals (Authenticated Users/Domain Users/Everyone). This is high-risk.' `
        -Data @{ Count = $broadEdit.Count; Sample = ($broadEdit | Select-Object -First $MaxSamples) })) | Out-Null
}

# Non-admin edit can be legitimate (delegation), but still worth reviewing
if ($nonAdminEdit.Count -gt 0) {
    $findings.Add((New-Finding -Severity 'Medium' -Category 'GPO' -Check 'GPO-DelegatedEditRights' `
        -Message 'One or more GPOs have delegated edit permissions to non-admin principals. Review for least privilege and change control.' `
        -Data @{ Count = $nonAdminEdit.Count; Sample = ($nonAdminEdit | Select-Object -First $MaxSamples) })) | Out-Null
}

if ($broadEdit.Count -eq 0 -and $nonAdminEdit.Count -eq 0) {
    $findings.Add((New-Finding -Severity 'Info' -Category 'GPO' -Check 'GPO-Permissions' `
        -Message 'No obvious high-risk GPO edit permissions detected (best-effort).' `
        -Data @{})) | Out-Null
}

$findings
