# Test-PerformanceBaselines.ps1
<#
.SYNOPSIS
Captures a lightweight performance snapshot (CPU, memory, disk latency, top processes) for triage and baselining.

.DESCRIPTION
Collects:
- CPU usage snapshot and core count
- Memory usage snapshot
- Disk I/O latency counters (if available)
- System drive queue length (best-effort)
- Top CPU processes (sampled)
- Top memory processes

WHEN TO USE
- "Server is slow" reports
- Post-patch performance issues
- Capacity planning baselines
- Evidence capture for escalation

NOTES
Read-only. Safe for production.
Perf counters vary by OS and may be unavailable if counters are corrupted; script records failures.
#>

[CmdletBinding()]
param(
    [int]$SampleSeconds = 3,
    [int]$TopProcesses  = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Try-GetCounter {
    param(
        [Parameter(Mandatory)][string[]]$CounterPath,
        [int]$SampleInterval = 1,
        [int]$MaxSamples = 1
    )

    try {
        $c = Get-Counter -Counter $CounterPath -SampleInterval $SampleInterval -MaxSamples $MaxSamples -ErrorAction Stop
        $c.CounterSamples | ForEach-Object {
            [pscustomobject]@{
                Path  = $_.Path
                Value = [math]::Round($_.CookedValue, 4)
            }
        }
    } catch {
        @(
            [pscustomobject]@{
                Path  = ($CounterPath -join ', ')
                Value = $null
                Note  = "Get-Counter failed: $($_.Exception.Message)"
            }
        )
    }
}

$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1

# CPU/memory quick snapshot
$cpuPct = $null
try {
    $cpuPct = (Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples $SampleSeconds -ErrorAction Stop).
        CounterSamples |
        Measure-Object -Property CookedValue -Average |
        Select-Object -ExpandProperty Average
    $cpuPct = [math]::Round($cpuPct, 2)
} catch { }

$memTotalGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
$memFreeGB  = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
$memUsedGB  = [math]::Round(($memTotalGB - $memFreeGB), 2)
$memUsedPct = if ($memTotalGB -gt 0) { [math]::Round(($memUsedGB / $memTotalGB) * 100, 2) } else { $null }

# Disk latency counters (best-effort)
$diskCounters = Try-GetCounter -CounterPath @(
    '\PhysicalDisk(_Total)\Avg. Disk sec/Read',
    '\PhysicalDisk(_Total)\Avg. Disk sec/Write',
    '\PhysicalDisk(_Total)\Current Disk Queue Length',
    '\LogicalDisk(_Total)\% Free Space'
) -SampleInterval 1 -MaxSamples 1

# Top processes by CPU (sample using Get-Process CPU deltas)
$topCpu = @()
try {
    $p1 = Get-Process | Select-Object Id, ProcessName, CPU
    Start-Sleep -Seconds ([Math]::Max(1, $SampleSeconds))
    $p2 = Get-Process | Select-Object Id, ProcessName, CPU

    $delta = foreach ($a in $p2) {
        $b = $p1 | Where-Object { $_.Id -eq $a.Id } | Select-Object -First 1
        if ($null -ne $b -and $null -ne $a.CPU -and $null -ne $b.CPU) {
            [pscustomobject]@{
                Id          = $a.Id
                ProcessName = $a.ProcessName
                CpuSecondsDelta = [math]::Round(($a.CPU - $b.CPU), 4)
            }
        }
    }

    $topCpu = $delta | Sort-Object CpuSecondsDelta -Descending | Select-Object -First $TopProcesses
} catch {
    $topCpu = @(
        [pscustomobject]@{
            Id=$null; ProcessName=$null; CpuSecondsDelta=$null; Note="Failed to compute CPU deltas: $($_.Exception.Message)"
        }
    )
}

# Top processes by memory
$topMem = @()
try {
    $topMem = Get-Process |
        Sort-Object WorkingSet64 -Descending |
        Select-Object -First $TopProcesses |
        ForEach-Object {
            [pscustomobject]@{
                Id          = $_.Id
                ProcessName = $_.ProcessName
                WorkingSetMB= [math]::Round($_.Work_
