param(
    [string]$Version = "1.0.0",
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$project = Join-Path $projectRoot "Pythia.WinUI.csproj"
$publish = Join-Path $projectRoot "publish\win-x64"
$projectRootFull = [System.IO.Path]::GetFullPath($projectRoot).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
$publishFull = [System.IO.Path]::GetFullPath($publish)
if (-not $publishFull.StartsWith("$projectRootFull$([System.IO.Path]::DirectorySeparatorChar)", [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to clean publish directory outside the project root: $publishFull"
}
$legacyWindowsRoot = Join-Path (Split-Path -Parent $projectRoot) "Pythia.Windows"
$prepareRuntime = Join-Path $legacyWindowsRoot "tool\prepare_plugin_runtime.ps1"
$preparedNode = Join-Path $legacyWindowsRoot "build\plugin_runtime\node.exe"
$installer = Join-Path $projectRoot "installer\Pythia.WinUI.iss"
$isccCandidates = @(
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
)
$iscc = $isccCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $iscc) {
    throw "Inno Setup 6 is required. Install it with: winget install JRSoftware.InnoSetup"
}
$chineseLanguageCommit = "eafc69c06f3b23bdccbf22d3fde83b499ddc4901"
$chineseLanguageSha256 = "6753be2c5e2740d859900fd902824db2ec568da5c5b52486524c9762d778b0b0"
$chineseLanguageFile = Join-Path $env:TEMP "Pythia-ChineseSimplified-$chineseLanguageCommit.isl"
$chineseLanguageUrl = "https://raw.githubusercontent.com/jrsoftware/issrc/$chineseLanguageCommit/Files/Languages/ChineseSimplified.isl"
if (-not (Test-Path -LiteralPath $chineseLanguageFile) -or
    (Get-FileHash -Algorithm SHA256 $chineseLanguageFile).Hash.ToLowerInvariant() -ne $chineseLanguageSha256) {
    Invoke-WebRequest -Uri $chineseLanguageUrl -OutFile $chineseLanguageFile
}
if ((Get-FileHash -Algorithm SHA256 $chineseLanguageFile).Hash.ToLowerInvariant() -ne $chineseLanguageSha256) {
    throw "Chinese Inno Setup language file checksum mismatch."
}

& $prepareRuntime
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $preparedNode)) {
    throw "Pythia plugin runtime preparation failed."
}

if (Test-Path -LiteralPath $publishFull) {
    Remove-Item -LiteralPath $publishFull -Recurse -Force
}

dotnet publish $project `
    --configuration $Configuration `
    --runtime win-x64 `
    --self-contained true `
    --output $publish `
    -p:Platform=x64 `
    -p:WindowsAppSDKSelfContained=true `
    -p:PublishReadyToRun=true `
    -p:PublishTrimmed=false
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed with exit code $LASTEXITCODE" }

$publishRuntime = Join-Path $publish "Runtime"
New-Item -ItemType Directory -Path $publishRuntime -Force | Out-Null
Copy-Item -LiteralPath $preparedNode -Destination (Join-Path $publishRuntime "node.exe") -Force
if (-not (Test-Path -LiteralPath (Join-Path $publishRuntime "node.exe"))) {
    throw "Published application is missing Runtime\node.exe."
}

& $iscc "/DAppVersion=$Version" "/DChineseLanguageFile=$chineseLanguageFile" $installer
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed with exit code $LASTEXITCODE" }

$artifact = Join-Path $projectRoot "dist\Pythia-$Version-windows-x64.exe"
if (-not (Test-Path -LiteralPath $artifact)) { throw "Installer was not created: $artifact" }
$checksum = "$artifact.sha256"
$hash = (Get-FileHash -Algorithm SHA256 $artifact).Hash.ToLowerInvariant()
"$hash  $(Split-Path -Leaf $artifact)" | Set-Content -LiteralPath $checksum -Encoding ascii -NoNewline
Get-Item -LiteralPath $artifact, $checksum | Select-Object FullName, Length, LastWriteTime
