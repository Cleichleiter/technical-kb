# Invoke-CloudHealthCheck.ps1
<#
.SYNOPSIS
Runs a standard suite of Cloud health checks (Azure + Entra + M365 + AAD Connect optional) and writes artifacts.

.DESCRIPTION
Orchestrates modular checks and writes per-check JSON outputs plus a Summary.json.
Designed for consistent evidence collection.

.PARAMETER OutputRoot
Root directory where run folders will be created.

.PARAMETER RunName
Optional custom name for the run folder. If not provided, a timestamp-based name is used.

.PARAMETER TenantId
Optional Azure tenant ID (used for Connect-AzAccount context targeting).

.PARAMETER SubscriptionId
Optional Azure subscription ID (sets context).

.PARAMETER Include
Which check groups to run.

.PARAMETER Skip
Checks to skip by script/check name.

.NOTES
Read-only by default. This script does not trigger AAD Connect sync automatically.
#>

[CmdletBinding()]
param(
    [string]$OutputRoot = (Join-Path $env:ProgramData 'TechnicalKB\CloudHealth'),
    [string]$RunName,
    [string]$TenantId,
    [string]$SubscriptionId,
    [ValidateSet('All','Azure','Entra','M365','AADConnect')]
    [string]$Include = 'All',
    [string[]]$Skip = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$shared = Join-Path $PSScriptRoot '_shared'
. (Join-Path $shared 'Write-CloudLog.ps1')
. (Join-Path $shared 'Assert-RunAsAdmin.ps1')
. (Join-Path $shared 'Assert-Module.ps1')

if (-not $RunName) {
    $RunName = "{0}-{1}" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmmss')
}

$runPath = Join-Path $OutputRoot $RunName
New-Item -ItemType Directory -Path $runPath -Force | Out-Null

$logPath = Join-Path $runPath 'run.log'
Write-CloudLog -Message "Starting Cloud health check. Include=$Include RunPath=$runPath" -Path $logPath

function Write-SectionJson {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][object]$Object
    )
    $path = Join-Path $runPath ("{0}.json" -f $Name)
    $Object | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Invoke-Section {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Script,
        [hashtable]$Args
    )

    if ($Skip -contains $Name -or $Skip -contains $Script) {
        Write-CloudLog -Message "Skipping: $Name" -Level WARN -Path $logPath
        return [pscustomobject]@{
            Section   = $Name
            Status    = 'SKIP'
            Timestamp = (Get-Date)
            Output    = $null
        }
    }

    Write-CloudLog -Message "Running: $Name ($Script)" -Path $logPath

    try {
        $result = & (Join-Path $PSScriptRoot $Script) @Args
        $outFile = Write-SectionJson -Name $Name -Object $result
        return [pscustomobject]@{
            Section   = $Name
            Status    = 'OK'
            Timestamp = (Get-Date)
            Output    = $outFile
        }
    } catch {
        $err = [pscustomobject]@{
            Section     = $Name
            Status      = 'FAIL'
            Timestamp   = (Get-Date)
            Error       = $_.Exception.Message
            Detail      = $_.ToString()
        }
        $outFile = Write-SectionJson -Name $Name -Object $err
        Write-CloudLog -Message "FAILED: $Name. $($_.Exception.Message)" -Level ERROR -Path $logPath
        return [pscustomobject]@{
            Section   = $Name
            Status    = 'FAIL'
            Timestamp = (Get-Date)
            Output    = $outFile
        }
    }
}

$sections = New-Object System.Collections.Generic.List[object]

# Azure checks
if ($Include -in @('All','Azure')) {
    $sections.Add((Invoke-Section -Name '01-AzureConnectivity' -Script 'Test-AzureConnectivity.ps1' -Args @{
        TenantId = $TenantId
        SubscriptionId = $SubscriptionId
    })) | Out-Null

    $sections.Add((Invoke-Section -Name '02-AzureSubscriptionInventory' -Script 'Get-AzureSubscriptionInventory.ps1' -Args @{
        SubscriptionId = $SubscriptionId
    })) | Out-Null

    $sections.Add((Invoke-Section -Name '03-AzureRBAC' -Script 'Test-AzureRBAC.ps1' -Args @{
        SubscriptionId = $SubscriptionId
    })) | Out-Null

    $sections.Add((Invoke-Section -Name '04-AzurePolicyCompliance' -Script 'Test-AzurePolicyCompliance.ps1' -Args @{
        SubscriptionId = $SubscriptionId
    })) | Out-Null

    $sections.Add((Invoke-Section -Name '05-AzureResourceLocks' -Script 'Test-AzureResourceLocks.ps1' -Args @{
        SubscriptionId = $SubscriptionId
    })) | Out-Null

    $sections.Add((Invoke-Section -Name '06-AzureKeyVaultHealth' -Script 'Test-AzureKeyVaultHealth.ps1' -Args @{
        SubscriptionId = $SubscriptionId
    })) | Out-Null

    $sections.Add((Invoke-Section -Name '07-AzureBackupHealth' -Script 'Test-AzureBackupHealth.ps1' -Args @{
        SubscriptionId = $SubscriptionId
    })) | Out-Null

    $sections.Add((Invoke-Section -Name '08-AzureAVDHealth' -Script 'Test-AzureAVDHealth.ps1' -Args @{
        SubscriptionId = $SubscriptionId
    })) | Out-Null
}

# Entra / Graph checks
if ($Include -in @('All','Entra')) {
    $sections.Add((Invoke-Section -Name '20-EntraIDDirectoryHealth' -Script 'Test-EntraIDDirectoryHealth.ps1' -Args @{})) | Out-Null
}

# M365 checks
if ($Include -in @('All','M365')) {
    $sections.Add((Invoke-Section -Name '30-M365ServiceHealth' -Script 'Get-M365ServiceHealth.ps1' -Args @{})) | Out-Null
}

# AAD Connect checks (on the AAD Connect server)
if ($Include -in @('All','AADConnect')) {
    if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'Test-AADConnectPrereqs.ps1')) {
        $sections.Add((Invoke-Section -Name '40-AADConnectPrereqs' -Script 'Test-AADConnectPrereqs.ps1' -Args @{})) | Out-Null
    }
    if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'Get-AADConnectSyncErrors.ps1')) {
        $sections.Add((Invoke-Section -Name '41-AADConnectSyncErrors' -Script 'Get-AADConnectSyncErrors.ps1' -Args @{})) | Out-Null
    }
}

$summary = [pscustomobject]@{
    ComputerName = $env:COMPUTERNAME
    Timestamp    = Get-Date
    Include      = $Include
    OutputPath   = $runPath
    SectionsOk   = @($sections | Where-Object { $_.Status -eq 'OK' }).Count
    SectionsFail = @($sections | Where-Object { $_.Status -eq 'FAIL' }).Count
    SectionsSkip = @($sections | Where-Object { $_.Status -eq 'SKIP' }).Count
    Sections     = $sections
    Log          = $logPath
}

$summaryPath = Write-SectionJson -Name 'Summary' -Object $summary
Write-CloudLog -Message "Completed Cloud health check. Summary=$summaryPath" -Path $logPath

$summary
