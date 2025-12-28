<#
.SYNOPSIS
Audits NTLM policy posture on Domain Controllers and optionally summarizes recent NTLM logon usage.

.DESCRIPTION
Reads key NTLM-related settings from DC registry via CIM:
- LmCompatibilityLevel
- RestrictSendingNTLMTraffic (client-side)
- NtlmMinClientSec / NtlmMinServerSec

Optionally counts NTLM logons from Security log (4624) for the last N days.
(Default: config-only; event log collection is optional and can be slow.)

.PARAMETER IncludeEventLogStats
If set, attempts to count NTLM logons (4624) per DC for the last -Days.

.PARAMETER Days
Days of event log history to scan when IncludeEventLogStats is set.

.EXAMPLE
.\Test-ADNTLMUsageAndPolicy.ps1
.EXAMPLE
.\Test-ADNTLMUsageAndPolicy.ps1 -IncludeEventLogStats -Days 7
#>

[CmdletBinding()]
param(
    [switch]$IncludeEventLogStats,
    [ValidateRange(1,90)]
    [int]$Days = 7
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

function Try-ImportAD {
    try { Import-Module ActiveDirectory -ErrorAction Stop; return $true } catch { return $false }
}

function Get-RemoteRegDWORD {
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][string]$SubKey,
        [Parameter(Mandatory)][string]$ValueName
    )

    $HKLM = 2147483650

    try {
        $reg = Get-CimInstance -ComputerName $ComputerName -Namespace root\cimv2 -ClassName StdRegProv -ErrorAction Stop
        $out = Invoke-CimMethod -InputObject $reg -MethodName GetDWORDValue -Arguments @{
            hDefKey     = $HKLM
            sSubKeyName = $SubKey
            sValueName  = $ValueName
        } -ErrorAction Stop

        if ($out.ReturnValue -ne 0) { return $null }
        return $out.uValue
    }
    catch {
        return $null
    }
}

function Get-NTLMLogonCount {
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][datetime]$StartTime
    )

    # Best-effort: query Security 4624 then filter for AuthenticationPackageName = NTLM
    try {
        $events = Get-WinEvent -ComputerName $ComputerName -FilterHashtable @{
            LogName   = 'Security'
            Id        = 4624
            StartTime = $StartTime
        } -ErrorAction Stop

        $count = 0
        foreach ($e in $events) {
            $xml = [xml]$e.ToXml()
            $apn = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'AuthenticationPackageName' }).'#text'
            if ($apn -eq 'NTLM') { $count++ }
        }
        return $count
    }
    catch {
        return $null
    }
}

if (-not (Try-ImportAD)) {
    return New-Finding -Severity 'Warning' -Category 'DCHardening' -Check 'NTLM-Policy' `
        -Message 'ActiveDirectory module not available. Run from a domain-joined admin workstation/server with RSAT.' `
        -Data @{ Module = 'ActiveDirectory' }
}

$dcList = @()
try { $dcList = Get-ADDomainController -Filter * | Sort-Object HostName } catch { $dcList = @() }

if (-not $dcList -or $dcList.Count -eq 0) {
    return New-Finding -Severity 'Warning' -Category 'DCHardening' -Check 'NTLM-Policy' `
        -Message 'No domain controllers discovered (or insufficient rights).' `
        -Data @{}
}

$lsaKey = 'SYSTEM\CurrentControlSet\Control\Lsa'
$msvKey = 'SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0'

$start = (Get-Date).AddDays(-$Days)

$results = foreach ($dc in $dcList) {
    $name = $dc.HostName

    $lmLevel   = Get-RemoteRegDWORD -ComputerName $name -SubKey $lsaKey -ValueName 'LmCompatibilityLevel'
    $restrict  = Get-RemoteRegDWORD -ComputerName $name -SubKey $lsaKey -ValueName 'RestrictSendingNTLMTraffic'
    $minClient = Get-RemoteRegDWORD -ComputerName $name -SubKey $msvKey -ValueName 'NtlmMinClientSec'
    $minServer = Get-RemoteRegDWORD -ComputerName $name -SubKey $msvKey -ValueName 'NtlmMinServerSec'

    $ntlmCount = $null
    if ($IncludeEventLogStats) {
        $ntlmCount = Get-NTLMLogonCount -ComputerName $name -StartTime $start
    }

    [pscustomobject]@{
        DomainController          = $name
        LmCompatibilityLevel      = $lmLevel
        LmCompatibilityMeaning    = switch ($lmLevel) {
            5 { 'Send NTLMv2 only; refuse LM & NTLM' }
            4 { 'Send NTLMv2 only; refuse LM' }
            3 { 'Send NTLMv2 only' }
            2 { 'Send NTLM respons
