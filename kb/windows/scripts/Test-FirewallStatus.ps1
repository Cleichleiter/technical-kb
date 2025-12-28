# Test-FirewallStatus.ps1
<#
.SYNOPSIS
Reports Windows Firewall profile status and high-signal configuration details.

.DESCRIPTION
Checks:
- MpsSvc (Windows Firewall service) status and start type
- Firewall profile states (Domain/Private/Public)
- Default inbound/outbound actions
- Optional: identifies if all profiles are disabled (high risk)
- Optional: captures a minimal set of enabled inbound allow rules (sample) for evidence

WHEN TO USE
- Baseline security validation
- Incident response
- Troubleshooting connectivity that might be firewall-related
- Hardening verification

NOTES
Read-only. Does not modify firewall configuration.
Get-NetFirewallProfile requires NetSecurity module (default on modern Windows).
#>

[CmdletBinding()]
param(
    [switch]$IncludeSampleInboundAllowRules,
    [int]$MaxRules = 200
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ServiceStartMode {
    param([Parameter(Mandatory)][string]$Name)
    try { (Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction Stop).StartMode }
    catch { $null }
}

$svc = Get-Service -Name 'MpsSvc' -ErrorAction SilentlyContinue
$svcStatus = if ($svc) { $svc.Status.ToString() } else { 'NotFound' }
$svcStart  = if ($svc) { (Get-ServiceStartMode -Name 'MpsSvc') } else { $null }

$profiles = @()
$profilesError = $null
try {
    $profiles = Get-NetFirewallProfile -ErrorAction Stop |
        Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction, NotifyOnListen, AllowInboundRules, AllowLocalFirewallRules
} catch {
    $profilesError = $_.Exception.Message
    $profiles = @()
}

$allDisabled = $false
if ($profiles.Count -gt 0) {
    $allDisabled = -not (@($profiles | Where-Object { $_.Enabled -eq $true }).Count -gt 0)
}

$rulesSample = $null
if ($IncludeSampleInboundAllowRules) {
    try {
        $rulesSample = Get-NetFirewallRule -Direction Inbound -Action Allow -Enabled True -ErrorAction Stop |
            Select-Object -First $MaxRules |
            Select-Object DisplayName, Name, Profile, Enabled, Direction, Action
    } catch {
        $rulesSample = @(
            [pscustomobject]@{
                DisplayName = $null
                Name        = $null
                Profile     = $null
                Enabled     = $null
                Direction   = 'Inbound'
                Action      = 'Allow'
                Note        = "Failed to query firewall rules: $($_.Exception.Message)"
            }
        )
    }
}

$issues = New-Object System.Collections.Generic.List[string]
if ($svcStatus -ne 'Running') { $issues.Add("Windows Firewall service (MpsSvc) not running (Status=$svcStatus).") | Out-Null }
if ($profilesError) { $issues.Add("Failed to query firewall profiles: $profilesError") | Out-Null }
if ($allDisabled) { $issues.Add('All firewall profiles appear disabled (high risk).') | Out-Null }

[pscustomobject]@{
    ComputerName    = $env:COMPUTERNAME
    Timestamp       = Get-Date

    FirewallService = [pscustomobject]@{
        Status    = $svcStatus
        StartType = $svcStart
    }

    Profiles        = $profiles
    AllProfilesDisabled = $allDisabled
    SampleInboundAllowRules = $rulesSample

    HasFirewallIssues = [bool]($issues.Count -gt 0)
    IssueReasons      = $issues
}
