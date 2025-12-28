<#
.SYNOPSIS
Collects baseline system context information for Windows health diagnostics.

.DESCRIPTION
Returns a lightweight snapshot of the system environment so diagnostic output
can be properly interpreted later.

Includes:
- Computer and OS details
- Boot time and uptime
- PowerShell version and edition
- Domain / workgroup membership
- Virtualization indicator (best-effort)
- Current user and elevation context

WHEN TO USE
- At the start of orchestrators
- When exporting health reports
- For incident evidence collection

.NOTES
Read-only. No dependencies on AD module.
#>

Set-StrictMode -Version Latest

function Get-SystemContext {
    [CmdletBinding()]
    param()

    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem

    $bootTime = $os.LastBootUpTime
    $uptime   = (Get-Date) - $bootTime

    $isAdmin = $false
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p  = New-Object Security.Principal.WindowsPrincipal($id)
        $isAdmin = $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {}

    [pscustomobject]@{
        ComputerName     = $env:COMPUTERNAME
        Domain           = $cs.Domain
        IsDomainJoined   = $cs.PartOfDomain
        Manufacturer     = $cs.Manufacturer
        Model            = $cs.Model
        IsVirtual        = ($cs.Model -match 'Virtual|VMware|Hyper-V|KVM')

        OS               = $os.Caption
        OSVersion        = $os.Version
        BuildNumber      = $os.BuildNumber
        InstallDate      = $os.InstallDate

        LastBootTime     = $bootTime
        UptimeDays       = [math]::Round($uptime.TotalDays, 2)

        PowerShell       = [pscustomobject]@{
            Version = $PSVersionTable.PSVersion.ToString()
            Edition = $PSVersionTable.PSEdition
        }

        UserContext      = [pscustomobject]@{
            UserName  = $env:USERNAME
            IsAdmin   = $isAdmin
        }

        Timestamp        = Get-Date
    }
}
