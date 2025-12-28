# Test-NetworkLatency.ps1
<#
.SYNOPSIS
Measures ICMP latency to one or more targets.

.DESCRIPTION
Per target:
- Sends multiple ICMP echo requests
- Reports min/avg/max latency and packet loss percentage

.PARAMETER Targets
Targets to test (IP/FQDN).

.PARAMETER Count
Number of samples per target.

.PARAMETER TimeoutSeconds
Timeout per ping.

.NOTES
Read-only. Safe for production.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]]$Targets,

    [ValidateRange(1,50)]
    [int]$Count = 10,

    [ValidateRange(1,10)]
    [int]$TimeoutSeconds = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$issues = New-Object System.Collections.Generic.List[string]
$results = New-Object System.Collections.Generic.List[object]

foreach ($t in $Targets) {
    $samples = @()
    $errors = 0

    for ($i = 1; $i -le $Count; $i++) {
        try {
            $r = Test-Connection -ComputerName $t -Count 1 -TimeoutSeconds $TimeoutSeconds -ErrorAction Stop
            $samples += [int]$r.ResponseTime
        } catch {
            $errors++
        }
    }

    $sent = $Count
    $received = $samples.Count
    $lossPct = if ($sent -gt 0) { [math]::Round((($sent - $received) / $sent) * 100, 1) } else { 0 }

    $min = if ($received -gt 0) { ($samples | Measure-Object -Minimum).Minimum } else { $null }
    $avg = if ($received -gt 0) { [math]::Round(($samples | Measure-Object -Average).Average, 1) } else { $null }
    $max = if ($received -gt 0) { ($samples | Measure-Object -Maximum).Maximum } else { $null }

    if ($lossPct -ge 10) {
        $issues.Add("Packet loss >= 10% detected for $t (Loss=$lossPct%).") | Out-Null
    }

    $results.Add([pscustomobject]@{
        Target     = $t
        Sent       = $sent
        Received   = $received
        LossPct    = $lossPct
        MinMs      = $min
        AvgMs      = $avg
        MaxMs      = $max
        SamplesMs  = $samples
    }) | Out-Null
}

[pscustomobject]@{
    Check        = 'NetworkLatency'
    Timestamp    = Get-Date
    Results      = $results
    HasIssues    = [bool]($issues.Count -gt 0)
    IssueReasons = $issues
}
