<#
.SYNOPSIS
Exports scheduled task inventory with action/trigger summaries and run-as context.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$OutputRoot,

    [Parameter()]
    [string]$LogPath,

    [Parameter()]
    [switch]$ExcludeMicrosoft,

    [Parameter()]
    [string]$ServerName = $env:COMPUTERNAME
)

$ErrorActionPreference = 'Stop'

function Write-LogLine { param([string]$Level,[string]$Message)
    if (Get-Command Write-MigrationLog -ErrorAction SilentlyContinue) { Write-MigrationLog -Level $Level -Message $Message -LogPath $LogPath }
    else { Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message" }
}

Write-LogLine INFO "Collecting scheduled tasks..."

$tasks = Get-ScheduledTask

if ($ExcludeMicrosoft) {
    $tasks = $tasks | Where-Object { $_.TaskPath -notlike "\Microsoft\*" }
}

$rows = foreach ($t in $tasks) {
    $info = $null
    try { $info = Get-ScheduledTaskInfo -TaskName $t.TaskName -TaskPath $t.TaskPath } catch { }

    $actions = @()
    try { $actions = $t.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" } } catch { }
    $triggers = @()
    try { $triggers = $t.Triggers | ForEach-Object { $_.ToString() } } catch { }

    [pscustomobject]@{
        TaskName        = $t.TaskName
        TaskPath        = $t.TaskPath
        State           = $t.State
        Author          = $t.Author
        RunAsUser       = $t.Principal.UserId
        LogonType       = $t.Principal.LogonType
        RunLevel        = $t.Principal.RunLevel
        LastRunTime     = if ($info) { $info.LastRunTime } else { $null }
        LastTaskResult  = if ($info) { $info.LastTaskResult } else { $null }
        NextRunTime     = if ($info) { $info.NextRunTime } else { $null }
        Actions         = ($actions -join ' | ')
        Triggers        = ($triggers -join ' | ')
    }
}

$rows | Export-Csv -LiteralPath (Join-Path $OutputRoot '07-ScheduledTasks.csv') -NoTypeInformation

Write-LogLine INFO "Scheduled task export complete."
