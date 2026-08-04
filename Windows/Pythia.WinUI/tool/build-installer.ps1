param(
    [string]$Version = "1.2.0",
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot

# Authenticode signing is optional and gated on environment variables so no certificate
# material ever lives in the repo. Provide either a PFX file + password, or a SHA-1 thumbprint
# of a cert in the current user's certificate store. When unset, the build produces an unsigned
# installer (tracked as EXT-1; the auto-updater accepts unsigned releases until a cert exists).
# When set, a signing failure aborts the release build.
$certFile = $env:PYTHIA_WIN_CERT_FILE
$certPassword = $env:PYTHIA_WIN_CERT_PASSWORD
$certSha1 = $env:PYTHIA_WIN_CERT_SHA1
$timestampServer = if ($env:PYTHIA_WIN_TIMESTAMP_URL) { $env:PYTHIA_WIN_TIMESTAMP_URL } else { 'http://timestamp.digicert.com' }

function Find-SignTool {
    $candidates = @(
        "$env:LOCALAPPDATA\Programs\WindowsSdk\AnyCPU\bin\x64\signtool.exe",
        "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\signtool.exe",
        "${env:ProgramFiles}\Windows Kits\10\bin\*\x64\signtool.exe"
    ) | ForEach-Object { Get-Item -Path $_ -ErrorAction SilentlyContinue } | Sort-Object FullName -Descending
    $found = $candidates | Select-Object -First 1
    if ($found) { return $found.FullName }
    $cmd = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw "signtool.exe not found. Install the Windows SDK or add signtool to PATH."
}

function Sign-File {
    param([string]$Path)
    if (-not $certFile -and -not $certSha1) {
        Write-Warning "PYTHIA_WIN_CERT_* not set — leaving '$(Split-Path -Leaf $Path)' unsigned (EXT-1). Not a signed release."
        return
    }
    $signtool = Find-SignTool
    if ($certFile) {
        if (-not (Test-Path -LiteralPath $certFile)) { throw "Certificate file not found: $certFile" }
        & $signtool sign /fd sha256 /td sha256 /tr $timestampServer /f $certFile /p $certPassword $Path
    }
    else {
        & $signtool sign /fd sha256 /td sha256 /tr $timestampServer /sha1 $certSha1 $Path
    }
    if ($LASTEXITCODE -ne 0) { throw "Authenticode signing failed for '$Path' (signtool exit $LASTEXITCODE). Aborting release build." }
    Write-Host "Signed: $Path"
}

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
    -p:PublishReadyToRun=false `
    -p:PublishTrimmed=false
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed with exit code $LASTEXITCODE" }

$publishRuntime = Join-Path $publish "Runtime"
New-Item -ItemType Directory -Path $publishRuntime -Force | Out-Null
Copy-Item -LiteralPath $preparedNode -Destination (Join-Path $publishRuntime "node.exe") -Force
if (-not (Test-Path -LiteralPath (Join-Path $publishRuntime "node.exe"))) {
    throw "Published application is missing Runtime\node.exe."
}

# Plugins are distributed separately. Never ship third-party plugin packages or an
# installed-plugin directory inside the application installer.
$bundledPlugins = Get-ChildItem -LiteralPath $publish -Recurse -File -ErrorAction Stop |
    Where-Object { $_.Extension -in '.pythia', '.potext' -or $_.FullName -match '[\\/]Plugins?[\\/]' }
if ($bundledPlugins) {
    $names = ($bundledPlugins | ForEach-Object FullName) -join [Environment]::NewLine
    throw "Publish tree contains bundled plugins, which are forbidden in release installers:$([Environment]::NewLine)$names"
}

# Sign the main executable before ISCC packages it, so the bundled Pythia.exe is signed too.
$mainExe = Join-Path $publish "Pythia.exe"
if (Test-Path -LiteralPath $mainExe) { Sign-File -Path $mainExe }

& $iscc "/DAppVersion=$Version" "/DChineseLanguageFile=$chineseLanguageFile" $installer
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed with exit code $LASTEXITCODE" }

$artifact = Join-Path $projectRoot "dist\Pythia-$Version-windows-x64.exe"
if (-not (Test-Path -LiteralPath $artifact)) { throw "Installer was not created: $artifact" }
# Sign the installer itself once ISCC has produced it.
Sign-File -Path $artifact
$checksum = "$artifact.sha256"
$hash = (Get-FileHash -Algorithm SHA256 $artifact).Hash.ToLowerInvariant()
"$hash  $(Split-Path -Leaf $artifact)" | Set-Content -LiteralPath $checksum -Encoding ascii -NoNewline
Get-Item -LiteralPath $artifact, $checksum | Select-Object FullName, Length, LastWriteTime
