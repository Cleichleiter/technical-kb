<#
.SYNOPSIS
Captures IIS site/app pool/binding configuration if IIS tools are available.
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

Write-LogLine INFO "Collecting IIS configuration snapshot..."

$outNote = Join-Path $OutputRoot '11-IIS-Notes.txt'

$hasWebAdmin = $false
try {
    Import-Module WebAdministration -ErrorAction Stop
    $hasWebAdmin = $true
} catch {
    $hasWebAdmin = $false
}

if (-not $hasWebAdmin) {
    "WebAdministration module not available. If this server hosts IIS, install IIS management tools or run from a host with IIS cmdlets." |
        Set-Content -LiteralPath $outNote -Encoding UTF8
    Write-LogLine INFO "IIS tools not present; wrote note."
    return
}

$sites = Get-Website | Select-Object Name, Id, State, PhysicalPath, ApplicationPool
$appPools = Get-ChildItem IIS:\AppPools | Select-Object Name, State, managedRuntimeVersion, managedPipelineMode, processModel

$bindings = New-Object System.Collections.Generic.List[object]
foreach ($s in $sites) {
    Get-WebBinding -Name $s.Name | ForEach-Object {
        $bindings.Add([pscustomobject]@{
            SiteName      = $s.Name
            Protocol      = $_.protocol
            BindingInfo   = $_.bindingInformation
            SslFlags      = $_.sslFlags
        })
    }
}

$sites | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputRoot '11-IIS-Sites.json') -Encoding UTF8
$appPools | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputRoot '11-IIS-AppPools.json') -Encoding UTF8
$bindings | Export-Csv -LiteralPath (Join-Path $OutputRoot '11-IIS-Bindings.csv') -NoTypeInformation

Write-LogLine INFO "IIS configuration snapshot complete."
