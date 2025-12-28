# Base path (example only – adjust per repo or project)
$BasePath   = 'C:\Example\Repo\kb\section-name'
$ScriptRoot = Join-Path $BasePath 'scripts'
$SharedRoot = Join-Path $ScriptRoot '_shared'

# Folders to create
$dirs = @(
    $BasePath
    $ScriptRoot
    $SharedRoot
)

# Files to create (0 KB placeholders)
$files = @(
    (Join-Path $SharedRoot 'Write-HealthLog.ps1')
    (Join-Path $SharedRoot 'Assert-RunAsAdmin.ps1')

    (Join-Path $ScriptRoot 'Invoke-HealthCheck.ps1')
    (Join-Path $ScriptRoot 'Export-HealthReport.ps1')
    (Join-Path $ScriptRoot 'Test-Prereqs.ps1')
    (Join-Path $ScriptRoot 'Get-CriticalEvents.ps1')
)

# Create folders
foreach ($d in $dirs) {
    if (-not (Test-Path -LiteralPath $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        Write-Host "Created folder: $d"
    } else {
        Write-Host "Exists:         $d"
    }
}

# Create files (no overwrite)
foreach ($f in $files) {
    if (-not (Test-Path -LiteralPath $f)) {
        New-Item -ItemType File -Path $f -Force | Out-Null
        Write-Host "Created file:   $f"
    } else {
        Write-Host "Exists:         $f"
    }
}

Write-Host ""
Write-Host "Scaffold complete."
