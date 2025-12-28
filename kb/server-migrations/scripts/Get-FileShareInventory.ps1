<#
.SYNOPSIS
Exports SMB share inventory and share-level access lists.
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

Write-LogLine INFO "Collecting SMB share inventory..."

$shares = @()
$access = New-Object System.Collections.Generic.List[object]

try {
    $shares = Get-SmbShare | Where-Object {
        $_.Name -notin @('ADMIN$','C$','IPC$') -and $_.Special -eq $false
    } | Select-Object Name, Path, Description, FolderEnumerationMode, CachingMode, EncryptData, ConcurrentUserLimit, ContinuouslyAvailable, AvailabilityType
}
catch {
    Write-LogLine WARN "Get-SmbShare failed: $($_.Exception.Message)"
}

foreach ($s in $shares) {
    try {
        $acl = Get-SmbShareAccess -Name $s.Name | Select-Object AccountName, AccessControlType, AccessRight
        foreach ($a in $acl) {
            $access.Add([pscustomobject]@{
                ShareName         = $s.Name
                SharePath         = $s.Path
                AccountName       = $a.AccountName
                AccessControlType = $a.AccessControlType
                AccessRight       = $a.AccessRight
            })
        }
    }
    catch {
        $access.Add([pscustomobject]@{
            ShareName         = $s.Name
            SharePath         = $s.Path
            AccountName       = $null
            AccessControlType = $null
            AccessRight       = $null
        })
    }
}

$sharesCsv = Join-Path $OutputRoot '03-Shares.csv'
$accessCsv = Join-Path $OutputRoot '03-SharePermissions.csv'

if ($shares) { $shares | Export-Csv -LiteralPath $sharesCsv -NoTypeInformation }
if ($access.Count -gt 0) { $access | Export-Csv -LiteralPath $accessCsv -NoTypeInformation }

Write-LogLine INFO "SMB share inventory complete."
