# Test-DefenderHealth.ps1
<#
.SYNOPSIS
Reports Microsoft Defender Antivirus / Defender for Endpoint health signals when available.

.DESCRIPTION
Uses built-in cmdlets where available:
- Get-MpComputerStatus (Defender AV)
- Optional: signature versions, last update, real-time protection state
- Optional: basic service checks (WinDefend, WdNisSvc, Sense)

WHEN TO USE
- Security baseline validation
- Incident response / suspected malware activity
- Verifying Defender is enabled and up to date
- Troubleshooting endpoint security policy conflicts

NOTES
Read-only.
On servers where Defender AV is not installed/active, Get-MpComputerStatus may not exist or may fail.
#>

[CmdletBinding()]
param(
    [switch]$IncludeServices
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ServiceStartMode {
    param([Parameter(Mandatory)][string]$Name)
    try { (Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction Stop).StartMode }
    catch { $null }
}

$mpStatus = $null
$mpError  = $null

if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
    try {
        $s = Get-MpComputerStatus -ErrorAction Stop

        $mpStatus = [pscustomobject]@{
            AMServiceEnabled              = $s.AMServiceEnabled
            AntispywareEnabled            = $s.AntispywareEnabled
            AntivirusEnabled              = $s.AntivirusEnabled
            BehaviorMonitorEnabled        = $s.BehaviorMonitorEnabled
            IoavProtectionEnabled         = $s.IoavProtectionEnabled
            NISEnabled                    = $s.NISEnabled
            OnAccessProtectionEnabled     = $s.OnAccessProtectionEnabled
            RealTimeProtectionEnabled     = $s.RealTimeProtectionEnabled

            AntispywareSignatureVersion   = $s.AntispywareSignatureVersion
            AntivirusSignatureVersion     = $s.AntivirusSignatureVersion
            NISSignatureVersion           = $s.NISSignatureVersion
            DefenderSignaturesOutOfDate   = $s.DefenderSignaturesOutOfDate

            FullScanAge                   = $s.FullScanAge
            QuickScanAge                  = $s.QuickScanAge

            TamperProtection              = $s.TamperProtection

            EngineVersion                 = $s.AMEngineVersion
            ProductVersion                = $s.AMProductVersion
            LastUpdated                   = $s.AntivirusSignatureLastUpdated
        }
    } catch {
        $mpError = $_.Exception.Message
    }
} else {
    $mpError = 'Get-MpComputerStatus cmdlet not available on this system.'
}

$services = $null
if ($IncludeServices) {
    $svcNames = @('WinDefend','WdNisSvc','Sense')
    $services = foreach ($n in $svcNames) {
        $svc = Get-Service -Name $n -ErrorAction SilentlyContinue
        if (-not $svc) {
            [pscustomobject]@{
                Name      = $n
                Present   = $false
                Status    = 'NotFound'
                StartType = $null
            }
        } else {
            [pscustomobject]@{
                Name      = $svc.Name
                Present   = $true
                Status    = $svc.Status.ToString()
                StartType = (Get-ServiceStartMode -Name $svc.Name)
            }
        }
    }
}

$issues = New-Object System.Collections.Generic.List[string]
if ($mpError) { $issues.Add($mpError) | Out-Null }

if ($mpStatus) {
    if ($mpStatus.DefenderSignaturesOutOfDate -eq $true) {
        $issues.Add('Defender signatures reported as out of date.') | Out-Null
    }
    if ($mpStatus.RealTimeProtectionEnabled -ne $true) {
        $issues.Add('Real-time protection is not enabled.') | Out-Null
    }
    if ($mpStatus.AntivirusEnabled -ne $true) {
        $issues.Add('Defender AV is not enabled.') | Out-Null
    }
}

[pscustomobject]@{
    ComputerName      = $env:COMPUTERNAME
    Timestamp         = Get-Date
    DefenderStatus    = $mpStatus
    DefenderError     = $mpError
    Services          = $services
    HasDefenderIssues = [bool]($issues.Count -gt 0)
    IssueReasons      = $issues
}
