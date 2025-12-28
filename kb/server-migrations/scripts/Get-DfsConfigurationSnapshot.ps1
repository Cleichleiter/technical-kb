<#
.SYNOPSIS
Captures DFS Namespace and DFS Replication configuration if DFS tools are available.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$OutputRoot,

    [Parameter()]
    [string]$LogPath,

    [Parameter()]
    [string]$ServerName = $env:COMPUTERNAME
)

$ErrorActionPreference = 'Stop'

function Write-LogLine { param([string]$Level,[string]$Message)
    if (Get-Command Write-MigrationLog -ErrorAction SilentlyContinue) { Write-MigrationLog -Level $Level -Message $Message -LogPath $LogPath }
    else { Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message" }
}

Write-LogLine INFO "Collecting DFS configuration snapshot..."

$outNote = Join-Path $OutputRoot '10-DFS-Notes.txt'

$hasDfsn = [bool](Get-Command Get-DfsnRoot -ErrorAction SilentlyContinue)
$hasDfsr = [bool](Get-Command Get-DfsReplicationGroup -ErrorAction SilentlyContinue)

if (-not $hasDfsn -and -not $hasDfsr) {
    "DFS cmdlets not available on this system. Install RSAT DFS tools or run on a management host with DFSN/DFSR modules." |
        Set-Content -LiteralPath $outNote -Encoding UTF8
    Write-LogLine INFO "DFS tools not present; wrote note."
    return
}

if ($hasDfsn) {
    try {
        $roots = Get-DfsnRoot -ErrorAction Stop
        $roots | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputRoot '10-DFSN-Roots.json') -Encoding UTF8

        $folders = New-Object System.Collections.Generic.List[object]
        $targets = New-Object System.Collections.Generic.List[object]

        foreach ($r in $roots) {
            $fs = Get-DfsnFolder -Path ($r.Path + '\*') -ErrorAction SilentlyContinue
            foreach ($f in $fs) {
                $folders.Add($f)
                $ts = Get-DfsnFolderTarget -Path $f.Path -ErrorAction SilentlyContinue
                foreach ($t in $ts) { $targets.Add($t) }
            }
        }

        $folders | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputRoot '10-DFSN-Folders.json') -Encoding UTF8
        $targets | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputRoot '10-DFSN-Targets.json') -Encoding UTF8
    } catch {
        "DFSN capture failed: $($_.Exception.Message)" | Set-Content -LiteralPath $outNote -Encoding UTF8
    }
}

if ($hasDfsr) {
    try {
        $groups = Get-DfsReplicationGroup -ErrorAction Stop
        $groups | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputRoot '10-DFSR-Groups.json') -Encoding UTF8

        $rf = New-Object System.Collections.Generic.List[object]
        $members = New-Object System.Collections.Generic.List[object]

        foreach ($g in $groups) {
            Get-DfsReplicatedFolder -GroupName $g.GroupName -ErrorAction SilentlyContinue | ForEach-Object { $rf.Add($_) }
            Get-DfsrMember -GroupName $g.GroupName -ErrorAction SilentlyContinue | ForEach-Object { $members.Add($_) }
        }

        $rf | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputRoot '10-DFSR-Folders.json') -Encoding UTF8
        $members | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputRoot '10-DFSR-Members.json') -Encoding UTF8
    } catch {
        "DFSR capture failed: $($_.Exception.Message)" | Set-Content -LiteralPath $outNote -Encoding UTF8
    }
}

Write-LogLine INFO "DFS configuration snapshot complete."
