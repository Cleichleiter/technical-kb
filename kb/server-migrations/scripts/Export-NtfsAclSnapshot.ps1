<#
.SYNOPSIS
Exports a snapshot of NTFS ACLs for specified root paths (typically share roots).

.DESCRIPTION
By default, this script attempts to identify SMB share paths and exports ACLs for those paths.
You can also provide explicit paths.

This is intentionally scoped to directories and intended to be practical for preflight (not a full crawl).

.PARAMETER Paths
One or more root paths to snapshot.

.PARAMETER MaxDepth
Directory depth to traverse beneath each root. Depth=0 means root only.

.PARAMETER OutputRoot
Destination folder for outputs.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string[]]$Paths,

    [Parameter()]
    [ValidateRange(0,50)]
    [int]$MaxDepth = 2,

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

function Get-DirectoriesWithDepth {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][int]$Depth
    )

    $results = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Path -LiteralPath $Root)) { return $results }

    $queue = New-Object System.Collections.Generic.Queue[object]
    $queue.Enqueue([pscustomobject]@{ Path=$Root; Level=0 })

    while ($queue.Count -gt 0) {
        $item = $queue.Dequeue()
        $results.Add($item.Path)

        if ($item.Level -ge $Depth) { continue }

        try {
            Get-ChildItem -LiteralPath $item.Path -Directory -Force -ErrorAction Stop | ForEach-Object {
                $queue.Enqueue([pscustomobject]@{ Path=$_.FullName; Level=($item.Level + 1) })
            }
        } catch {
            # ignore inaccessible folders during preflight snapshot
            continue
        }
    }

    return $results
}

Write-LogLine INFO "Exporting NTFS ACL snapshot..."

# Default to share paths if no explicit paths provided
if (-not $Paths -or $Paths.Count -eq 0) {
    try {
        $Paths = (Get-SmbShare | Where-Object { $_.Name -notin @('ADMIN$','C$','IPC$') -and $_.Special -eq $false } |
            Select-Object -ExpandProperty Path -Unique)
        Write-LogLine INFO "No -Paths provided. Using SMB shar
