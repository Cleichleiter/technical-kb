# Test-MTU.ps1
<#
.SYNOPSIS
Performs an MTU discovery test to identify common fragmentation problems.

.DESCRIPTION
Uses ping with the "Don't Fragment" flag to determine the largest payload
that succeeds (best-effort). This can help diagnose VPN/IPSec path MTU issues.

.PARAMETER Target
Target to test against. Default is a reliable public resolver.

.PARAMETER StartPayloadBytes
Starting payload size (not including ICMP headers).

.PARAMETER MinPayloadBytes
Minimum payload size to stop searching.

.PARAMETER StepBytes
Decrement step during search.

.NOTES
Read-only. Safe for production.
#>

[CmdletBinding()]
param(
    [string]$Target = '1.1.1.1',
    [ValidateRange(500,2000)]
    [int]$StartPayloadBytes = 1472,
    [ValidateRange(200,2000)]
    [int]$MinPayloadBytes = 1200,
    [ValidateRange(1,100)]
    [int]$StepBytes = 10,
    [ValidateRange(1,5)]
    [int]$TimeoutSeconds = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$issues = New-Object System.Collections.Generic.List[string]

function Test-DFPing {
    param(
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][int]$PayloadBytes
    )
    try {
        # Windows ping: -f sets DF, -l sets payload size
        $out = & ping.exe $Target -n 1 -w ($TimeoutSeconds * 1000) -f -l $PayloadBytes 2>&1
        if ($LASTEXITCODE -eq 0 -and ($out -match 'Reply from')) { return $true }
        return $false
    } catch { return $false }
}

$payload = $StartPayloadBytes
$best = $null

while ($payload -ge $MinPayloadBytes) {
    $ok = Test-DFPing -Target $Target -PayloadBytes $payload
    if ($ok) {
        $best = $payload
        break
    }
    $payload -= $StepBytes
}

# Approximate MTU = payload + 28 bytes (IPv4 header 20 + ICMP 8)
$mtu = if ($best) { $best + 28 } else { $null }

if (-not $best) {
    $issues.Add("Unable to find a working DF payload size down to $MinPayloadBytes bytes for target $Target.") | Out-Null
}

[pscustomobject]@{
    Check             = 'MTU'
    Timestamp         = Get-Date
    Target            = $Target
    StartPayloadBytes = $StartPayloadBytes
    BestPayloadBytes  = $best
    ApproxMTU         = $mtu
    HasIssues         = [bool]($issues.Count -gt 0)
    IssueReasons      = $issues
}
