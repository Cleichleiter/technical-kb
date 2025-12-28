<#
.SYNOPSIS
Creates a lightweight security baseline snapshot from all GPOs and optionally diffs against a prior snapshot.

.DESCRIPTION
- Generates XML reports for all GPOs and extracts key metadata:
  - GPO name, GUID, modification time
  - Links (where discoverable)
  - Computer/User enabled
- Outputs a snapshot JSON object
- If -BaselinePath is provided, compares and reports:
  - New/removed GPOs
  - Modified GPOs (by ModTime)
This is intended to support change detection, not full policy parsing.

PARAMETER OutputPath
Where to write the snapshot JSON.

PARAMETER BaselinePath
Path to a previous snapshot JSON for diffing.

OUTPUT
Finding objects.

.EXAMPLE
.\Get-GPOSecurityBaselineDiff.ps1 -OutputPath C:\Reports\gpo-snapshot.json

.EXAMPLE
.\Get-GPOSecurityBaselineDiff.ps1 -OutputPath .\current.json -BaselinePath .\previous.json
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath,

    [Parameter(Mandatory=$false)]
    [string]$BaselinePath
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
    return New-Finding -Severity 'Warning' -Category 'GPO' -Check 'GPO-Baseline-Diff' `
        -Message 'GroupPolicy module not available (RSAT required).' `
        -Data @{ Module = 'GroupPolicy' }
}

# Build current snapshot
$gpos = Get-GPO -All -ErrorAction Stop

$snapshot = foreach ($gpo in $gpos) {
    [pscustomobject]@{
        Name              = $gpo.DisplayName
        Id                = [string]$gpo.Id
        CreationTime      = $gpo.CreationTimeUtc
        ModificationTime  = $gpo.ModificationTimeUtc
        GpoStatus         = [string]$gpo.GpoStatus
        ComputerEnabled   = -not ($gpo.GpoStatus -in @('ComputerSettingsDisabled','AllSettingsDisabled'))
        UserEnabled       = -not ($gpo.GpoStatus -in @('UserSettingsDisabled','AllSettingsDisabled'))
    }
}

# Write snapshot JSON
$dir = Split-Path -Parent $OutputPath
if ($dir -and -not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}
$snapshot | ConvertTo-Json -Depth 6 | Out-File -FilePath $OutputPath -Encoding utf8

$findings = New-Object System.Collections.Generic.List[object]
$findings.Add((New-Finding -Severity 'Info' -Category 'GPO' -Check 'GPO-Baseline-Snapshot' `
    -Message "Wrote current GPO snapshot to: $OutputPath" `
    -Data @{ GPOCount = $snapshot.Count; OutputPath = $OutputPath })) | Out-Null

# Optional diff
if ($BaselinePath) {
    if (-not (Test-Path -LiteralPath $BaselinePath)) {
        $findings.Add((New-Finding -Severity 'Warning' -Category 'GPO' -Check 'GPO-Baseline-Diff' `
            -Message "BaselinePath not found: $BaselinePath" `
            -Data @{ BaselinePath = $BaselinePath })) | Out-Null
        $findings
        return
    }

    $baseline = Get-Content -LiteralPath $BaselinePath -Raw -Encoding utf8 | ConvertFrom-Json

    $baseById = @{}
    foreach ($b in $baseline) { $baseById[[string]$b.Id] = $b }

    $currById = @{}
    foreach ($c in $snapshot) { $currById[[string]$c.Id] = $c }

    $new    = $snapshot | Where-Object { -not $baseById.ContainsKey([string]$_.Id) }
    $removed= $baseline | Where-Object { -not $currById.ContainsKey([string]$_.Id) }
    $changed= $snapshot | Where-Object {
        $id = [string]$_.Id
        $baseById.ContainsKey($id) -and ($_.ModificationTime -ne $baseById[$id].ModificationTime)
    }

    if ($new.Count -gt 0 -or $removed.Count -gt 0 -or $changed.Count -gt 0) {
        $findings.Add((New-Finding -Severity 'Medium' -Category 'GPO' -Check 'GPO-Baseline-Diff' `
            -Message 'GPO baseline drift detected (new/removed/modified GPOs). Review change control.' `
            -Data @{
                BaselinePath = $BaselinePath
                CurrentPath  = $OutputPath
                NewCount     = $new.Count
                RemovedCount = $removed.Count
                ChangedCount = $changed.Count
                NewSample    = $new | Select-Object -First 25 Name, Id, ModificationTime
                RemovedSample= $removed | Select-Object -First 25 Name, Id, ModificationTime
                ChangedSample= $changed | Select-Object -First 25 Name, Id, ModificationTime
            })) | Out-Null
    }
    else {
        $findings.Add((New-Finding -Severity 'Info' -Category 'GPO' -Check 'GPO-Baseline-Diff' `
            -Message 'No baseline drift detected (by GPO modification timestamps).' `
            -Data @{ BaselinePath = $BaselinePath; CurrentPath = $OutputPath })) | Out-Null
    }
}

$findings
