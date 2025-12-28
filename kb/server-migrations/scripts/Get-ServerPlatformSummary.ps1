<#
.SYNOPSIS
Collects platform/OS/network summary for migration preflight.

.PARAMETER OutputRoot
Destination folder for outputs.

.PARAMETER LogPath
Optional log file path (shared logging).

.PARAMETER ServerName
Server name label used in outputs.
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

function Write-LogLine {
    param([string]$Level,[string]$Message)
    if (Get-Command -Name Write-MigrationLog -ErrorAction SilentlyContinue) {
        Write-MigrationLog -Level $Level -Message $Message -LogPath $LogPath
    } else {
        Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    }
}

Write-LogLine INFO "Collecting platform summary..."

$os  = Get-CimInstance Win32_OperatingSystem
$cs  = Get-CimInstance Win32_ComputerSystem
$bios = Get-CimInstance Win32_BIOS

$hotfix = $null
try { $hotfix = Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 25 } catch { }

$adapters = @()
$ipAddrs  = @()
try { $adapters = Get-NetAdapter | Select-Object Name, InterfaceDescription, Status, LinkSpeed, MacAddress } catch { }
try { $ipAddrs  = Get-NetIPAddress | Where-Object { $_.IPAddress -and $_.AddressFamily -in @('IPv4','IPv6') } |
        Select-Object InterfaceAlias, AddressFamily, IPAddress, PrefixLength, DefaultGateway } catch { }

$summary = [pscustomobject]@{
    ServerName        = $ServerName
    ComputerName      = $env:COMPUTERNAME
    Domain            = $cs.Domain
    PartOfDomain      = $cs.PartOfDomain
    Manufacturer      = $cs.Manufacturer
    Model             = $cs.Model
    TotalPhysicalGB   = [math]::Round(($cs.TotalPhysicalMemory / 1GB), 2)
    OSName            = $os.Caption
    OSVersion         = $os.Version
    OSBuildNumber     = $os.BuildNumber
    InstallDate       = $os.InstallDate
    LastBootUpTime    = $os.LastBootUpTime
    UptimeDays        = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalDays, 2)
    SerialNumber      = $bios.SerialNumber
    BIOSVersion       = ($bios.SMBIOSBIOSVersion -join '; ')
    TimeZone          = (Get-TimeZone).Id
    PSVersion         = $PSVersionTable.PSVersion.ToString()
}

$summaryPath = Join-Path $OutputRoot '01-SystemSummary.json'
$txtPath     = Join-Path $OutputRoot '01-SystemSummary.txt'
$hotfixPath  = Join-Path $OutputRoot '01-HotFixes.csv'
$nicPath     = Join-Path $OutputRoot '01-NetworkAdapters.csv'
$ipPath      = Join-Path $OutputRoot '01-IPAddresses.csv'

$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

@(
    "ServerName:        $($summary.ServerName)"
    "ComputerName:      $($summary.ComputerName)"
    "Domain:            $($summary.Domain)"
    "PartOfDomain:      $($summary.PartOfDomain)"
    "Manufacturer:      $($summary.Manufacturer)"
    "Model:             $($summary.Model)"
    "TotalPhysicalGB:   $($summary.TotalPhysicalGB)"
    "OS:                $($summary.OSName)"
    "OSVersion:         $($summary.OSVersion)"
    "Build:             $($summary.OSBuildNumber)"
    "InstallDate:       $($summary.InstallDate)"
    "LastBootUpTime:    $($summary.LastBootUpTime)"
    "UptimeDays:        $($summary.UptimeDays)"
    "SerialNumber:      $($summary.SerialNumber)"
    "BIOSVersion:       $($summary.BIOSVersion)"
    "TimeZone:          $($summary.TimeZone)"
    "PowerShell:        $($summary.PSVersion)"
) | Set-Content -LiteralPath $txtPath -Encoding UTF8

if ($hotfix) { $hotfix | Export-Csv -LiteralPath $hotfixPath -NoTypeInformation }
if ($adapters) { $adapters | Export-Csv -LiteralPath $nicPath -NoTypeInformation }
if ($ipAddrs)   { $ipAddrs  | Export-Csv -LiteralPath $ipPath -NoTypeInformation }

Write-LogLine INFO "Platform summary complete."
