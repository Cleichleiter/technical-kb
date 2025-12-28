# Test-BackupPrereqs.ps1
<#
.SYNOPSIS
Validates baseline prerequisites commonly required for reliable backups on Windows.

.DESCRIPTION
Checks:
- Required services (RPC, VSS, COM+)
- VSS service state
- Presence of vssadmin and wbadmin (best-effort)
- Basic WMI/CIM access (used by inventory/restore checks)

.NOTES
Read-only. Safe for production.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$issues = New-Object System.Collections.Generic.List[string]

$svcList = @(
    'RpcSs',      # Remote Procedure Call
    'VSS',        # Volume Shadow Copy
    'COMSysApp'   # COM+ System Application
)

$services = foreach ($s in $svcList) {
    $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
    if (-not $svc) {
        $issues.Add("Service not found: $s") | Out-Null
        [pscustomobject]@{ Name=$s; Status=$null; StartType=$null }
        continue
    }

    if ($svc.Status -ne 'Running') {
        $issues.Add("Service not running: $s (Status=$($svc.Status))") | Out-Null
    }

    $startType = $null
    try {
        $wmi = Get-CimInstance Win32_Service -Filter "Name='$s'" -ErrorAction Stop
        $startType = $wmi.StartMode
    } catch {
        $issues.Add("Unable to query service start mode via CIM for $s: $($_.Exception.Message)") | Out-Null
    }

    [pscustomobject]@{
        Name      = $s
        Status    = $svc.Status
        StartType = $startType
    }
}

# Tooling presence (best-effort)
$vssadmin = $null
$wbadmin  = $null
try { $vssadmin = (Get-Command vssadmin.exe -ErrorAction Stop).Source } catch { $vssadmin = $null }
try { $wbadmin  = (Get-Command wbadmin.exe  -ErrorAction Stop).Source } catch { $wbadmin  = $null }

if (-not $vssadmin) {
    $issues.Add("vssadmin.exe not found. VSS diagnostics may be limited.") | Out-Null
}

# wbadmin is informational; not present on all SKUs
$cimOk = $true
try {
    [void](Get-CimInstance Win32_OperatingSystem -ErrorAction Stop)
} catch {
    $cimOk = $false
    $issues.Add("CIM/WMI query failed (Win32_OperatingSystem): $($_.Exception.Message)") | Out-Null
}

[pscustomobject]@{
    Check        = 'BackupPrereqs'
    Timestamp    = Get-Date
    Services     = $services
    Tools        = [pscustomobject]@{
        Vssadmin = $vssadmin
        Wbadmin  = $wbadmin
    }
    CimAvailable = $cimOk
    HasIssues    = [bool]($issues.Count -gt 0)
    IssueReasons = $issues
}
