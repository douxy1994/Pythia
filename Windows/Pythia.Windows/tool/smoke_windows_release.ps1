[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ReleaseDirectory,

    [Parameter(Mandatory = $true)]
    [string]$InstallerPath,

    [int]$StartupSeconds = 6
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$release = (Resolve-Path $ReleaseDirectory).Path
$installer = (Resolve-Path $InstallerPath).Path
$rawExecutable = Join-Path $release "Pythia.exe"
$tempRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [System.IO.Path]::GetTempPath() }
$smokeRoot = Join-Path $tempRoot "pythia-runtime-smoke"
$installDirectory = Join-Path $smokeRoot "Installed"
$runtimeLog = Join-Path $smokeRoot "runtime.log"
$installLog = Join-Path $smokeRoot "install.log"
$uninstallLog = Join-Path $smokeRoot "uninstall.log"

if ($StartupSeconds -lt 2 -or $StartupSeconds -gt 30) {
    throw "StartupSeconds must be between 2 and 30."
}
if (-not (Test-Path $rawExecutable -PathType Leaf)) {
    throw "Pythia.exe is missing from the release directory: $rawExecutable"
}

New-Item -ItemType Directory -Path $smokeRoot -Force | Out-Null

function Stop-PythiaProcesses {
    Get-Process -Name "Pythia" -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
}

function Assert-PythiaProcessHealthy {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Executable,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    if (-not (Test-Path $Executable -PathType Leaf)) {
        throw "$Label executable is missing: $Executable"
    }

    $process = Start-Process -FilePath $Executable -PassThru
    try {
        $deadline = [DateTime]::UtcNow.AddSeconds($StartupSeconds)
        do {
            Start-Sleep -Milliseconds 250
            $process.Refresh()
            if ($process.HasExited) {
                throw "$Label exited during startup with code $($process.ExitCode)."
            }
        } while ($process.MainWindowHandle -eq 0 -and [DateTime]::UtcNow -lt $deadline)

        if ($process.MainWindowHandle -eq 0) {
            throw "$Label did not create a main window within $StartupSeconds seconds."
        }
        if (-not $process.Responding) {
            throw "$Label created a window but it is not responding."
        }
        Write-Host "$Label created a responsive main window (PID $($process.Id), HWND $($process.MainWindowHandle))."
    } finally {
        if (-not $process.HasExited) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            Wait-Process -Id $process.Id -Timeout 10 -ErrorAction SilentlyContinue
        }
    }
}

$transcriptStarted = $false
try {
    Start-Transcript -Path $runtimeLog -Force | Out-Null
    $transcriptStarted = $true
    Stop-PythiaProcesses
    Assert-PythiaProcessHealthy -Executable $rawExecutable -Label "Pythia raw release start"
    Assert-PythiaProcessHealthy -Executable $rawExecutable -Label "Pythia raw release restart"

    if (Test-Path $installDirectory) {
        Remove-Item $installDirectory -Recurse -Force
    }
    $installProcess = Start-Process -FilePath $installer -ArgumentList @(
        "/VERYSILENT",
        "/SUPPRESSMSGBOXES",
        "/NORESTART",
        "/DIR=$installDirectory",
        "/LOG=$installLog"
    ) -Wait -PassThru
    if ($installProcess.ExitCode -ne 0) {
        throw "Pythia installer failed with exit code $($installProcess.ExitCode). See $installLog"
    }

    $installedExecutable = Join-Path $installDirectory "Pythia.exe"
    Assert-PythiaProcessHealthy -Executable $installedExecutable -Label "Installed Pythia start"

    $uninstaller = Join-Path $installDirectory "unins000.exe"
    if (-not (Test-Path $uninstaller -PathType Leaf)) {
        throw "Pythia uninstaller is missing: $uninstaller"
    }
    $uninstallProcess = Start-Process -FilePath $uninstaller -ArgumentList @(
        "/VERYSILENT",
        "/SUPPRESSMSGBOXES",
        "/NORESTART",
        "/LOG=$uninstallLog"
    ) -Wait -PassThru
    if ($uninstallProcess.ExitCode -ne 0) {
        throw "Pythia uninstaller failed with exit code $($uninstallProcess.ExitCode). See $uninstallLog"
    }
    if (Test-Path $installedExecutable) {
        throw "Pythia.exe remained after uninstall: $installedExecutable"
    }

    Write-Host "Pythia Windows runtime, restart, install, launch, and uninstall smoke test passed."
} finally {
    Stop-PythiaProcesses
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
