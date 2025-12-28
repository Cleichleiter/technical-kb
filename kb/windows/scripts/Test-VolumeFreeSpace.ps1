# Test-VolumeFreeSpace.ps1
<#
.SYNOPSIS
Checks volume free space and flags low space conditions using configurable thresholds.

.DESCRIPTION
Enumerates local fixed disks and calculates:
- Size (GB)
- Free space (GB)
- Free percent
Flags volumes below thresholds. Also highlights the OS volume separately.

WHEN TO USE
- Patch failures
- Performance degradation
- Unexpected application errors
- Prior to migrations or large data operations
- Routine baselining and capacity checks

.NOTES
Read-only. Safe for production.
#>

[CmdletBinding()]
param(
    # Default thresholds
    [ValidateRange(1,99)]
    [int]$WarnPercent = 15,

    [ValidateRange(1,99)]
    [int]$FailPercent = 10,

    # OS volume can have stricter thresholds
    [ValidateRange(1,99)]
    [int]$OSWarnPercent = 20,

    [ValidateRange(1,99)]
    [int]$OSFailPercent = 15
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$osDrive = $env:SystemDrive.TrimEnd('\')

$disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | # 3 = local fixed disk
    ForEach-Object {
        $freePct = if ($_.Size -gt 0) { [math]::Round(($_.FreeSpace / $_.Size) * 100, 2) } else { $null }
        $isOS = ($_.DeviceID -eq $osDrive)

        $warn = if ($isOS) { $OSWarnPercent } else { $WarnPercent }
        $fail = if ($isOS) { $OSFailPercent } else { $FailPercent }

        $state =
            if ($null -eq $freePct) { 'UNKNOWN' }
            elseif ($freePct -le $fail) { 'FAIL' }
            elseif ($freePct -le $warn) { 'WARN' }
            else { 'OK' }

        [pscustomobject]@{
            Drive       = $_.DeviceID
            VolumeName  = $_.VolumeName
            FileSystem  = $_.FileSystem
            IsOSVolume  = $isOS
            SizeGB      = [math]::Round($_.Size / 1GB, 2)
            FreeGB      = [math]::Round($_.FreeSpace / 1GB, 2)
            FreePercent = $freePct
            Thresholds  = [pscustomobject]@{
                WarnPercent = $warn
                FailPercent = $fail
            }
            State       = $state
        }
    }

$problems = $disks | Where-Object { $_.State -in @('WARN','FAIL','UNKNOWN') }

[pscustomobject]@{
    ComputerName = $env:COMPUTERNAME
    Timestamp    = Get-Date
    OSDrive      = $osDrive
    ProblemCount = @($problems).Count
    Problems     = $problems
    Volumes      = $disks | Sort-Object Drive
}
