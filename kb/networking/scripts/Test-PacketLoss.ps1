<#
.SYNOPSIS
Detects intermittent packet loss by running repeated ICMP probes over time.

.DESCRIPTION
Designed for identifying unstable WAN/Wi-Fi/VPN links.
Per target, sends probes and summarizes loss rate and streaks.

.PARAMETER Targets
Targets to test.

.PARAMETER Count
Number of probes per target.

.PARAMETER IntervalMs
Delay between probes.

.PARAMETER TimeoutSeconds
Timeout per probe.

.NOTES
Read-only. Safe for production.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]]$Targets,

    [ValidateRange(5,200)]
    [int]$Count = 50,

    [ValidateRange(10,5000)]
    [int]$IntervalMs = 200,

    [ValidateRange(1,10)]
    [int]$TimeoutSeconds = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$issues = New-Object System.Collections.Generic.List[string]
$results = New-Object System.Collections.Generic.List[object]

foreach ($t in $Targets) {
    $sent = 0
    $received = 0
    $timeline = New-Object System.Collections.Generic.List[object]

    $currentFailStreak = 0
    $maxFailStreak = 0

    for ($i = 1; $i -le $Count; $i++) {
        $sent++
        $ok = $false
        $ms = $null

        try {
            $r = Test-Connection -ComputerName $t -Count 1 -TimeoutSeconds $TimeoutSeconds -ErrorAction Stop
            $ok = $true
            $ms = [int]$r.ResponseTime
        } catch {
            $ok = $false
        }

        if ($ok) {
            $received++
            $currentFailStreak = 0
        } else {
            $currentFailStreak++
            if ($currentFailStreak -gt $maxFailStreak) { $maxFailStreak = $currentFailStreak }
        }

        $timeline.Add([pscustomobject]@{
            Seq       = $i
            Time      = Get-Date
            Success   = $ok
            LatencyMs = $ms
        }) | Out-Null

        Start-Sleep -Milliseconds $IntervalMs
    }

    $lossPct = if ($sent -gt 0) { [math]::Round((($sent - $received) / $sent) * 100, 1) } else { 0 }

    if ($lossPct -ge 5) {
        $issues.Add("Packet loss >= 5% detected for $t (Loss=$lossPct%).") | Out-Null
    }
    if ($maxFailStreak -ge 3) {
        $issues.Add("Consecutive ping failures detected for $t (MaxFailStreak=$maxFailStreak).") | Out-Null
    }

    $results.Add([pscustomobject]@{
        Target        = $t
        Sent          = $sent
        Received      = $received
        LossPct       = $lossPct
        MaxFailStreak = $maxFailStreak
        Timeline      = $timeline
    }) | Out-Null
}

[pscustomobject]@{
    Check        = 'PacketLoss'
    Timestamp    = Get-Date
    Results      = $results
    HasIssues    = [bool]($issues.Count -gt 0)
    IssueReasons = $issues
}
