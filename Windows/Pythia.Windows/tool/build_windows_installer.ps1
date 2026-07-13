$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$release = Join-Path $root "build\windows\x64\runner\Release"
$dist = Join-Path $root "dist"
$installer = Join-Path $dist "Pythia-1.0.0-windows-x64.exe"
$checksum = "$installer.sha256"
$isccCandidates = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
)
$iscc = $isccCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
$chineseLanguageCommit = "eafc69c06f3b23bdccbf22d3fde83b499ddc4901"
$chineseLanguageSha256 = "6753be2c5e2740d859900fd902824db2ec568da5c5b52486524c9762d778b0b0"
$chineseLanguageFile = Join-Path $env:TEMP "Pythia-ChineseSimplified-$chineseLanguageCommit.isl"
$chineseLanguageUrl = "https://raw.githubusercontent.com/jrsoftware/issrc/$chineseLanguageCommit/Files/Languages/ChineseSimplified.isl"

if (-not (Test-Path $release)) {
    throw "Windows x64 release directory does not exist: $release"
}
if (-not $iscc) {
    throw "Inno Setup 6 compiler was not found. Install it before packaging."
}

if (-not (Test-Path $chineseLanguageFile) -or
    (Get-FileHash -Algorithm SHA256 $chineseLanguageFile).Hash.ToLowerInvariant() -ne $chineseLanguageSha256) {
    Invoke-WebRequest -Uri $chineseLanguageUrl -OutFile $chineseLanguageFile
}
$actualLanguageHash = (Get-FileHash -Algorithm SHA256 $chineseLanguageFile).Hash.ToLowerInvariant()
if ($actualLanguageHash -ne $chineseLanguageSha256) {
    Remove-Item $chineseLanguageFile -Force -ErrorAction SilentlyContinue
    throw "Chinese Inno Setup language file checksum mismatch."
}

Push-Location $root
try {
    dart run tool/verify_release_package.dart $release
    New-Item -ItemType Directory -Path $dist -Force | Out-Null
    & $iscc "/DChineseLanguageFile=$chineseLanguageFile" "installer\Pythia.iss"
    if ($LASTEXITCODE -ne 0) {
        throw "Inno Setup failed with exit code $LASTEXITCODE"
    }
    if ($env:PYTHIA_WINDOWS_CERT_SHA1) {
        $signTool = Get-Command "signtool.exe" -ErrorAction SilentlyContinue
        if (-not $signTool) {
            throw "PYTHIA_WINDOWS_CERT_SHA1 is set, but signtool.exe was not found."
        }
        & $signTool.Source sign /sha1 $env:PYTHIA_WINDOWS_CERT_SHA1 /fd SHA256 /tr "http://timestamp.digicert.com" /td SHA256 $installer
        if ($LASTEXITCODE -ne 0) {
            throw "Authenticode signing failed with exit code $LASTEXITCODE"
        }
    } else {
        Write-Warning "Installer is an unsigned CI candidate. Production auto-update requires Authenticode signing."
    }
    $hash = (Get-FileHash -Algorithm SHA256 $installer).Hash.ToLowerInvariant()
    "$hash  $(Split-Path -Leaf $installer)" | Set-Content -Encoding ascii -NoNewline $checksum
    Write-Host "Created $installer"
    Write-Host "Created $checksum"
} finally {
    Pop-Location
}
