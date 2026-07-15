$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$version = "v24.18.0"
$archiveName = "node-$version-win-x64.zip"
$expectedSha256 = "0ae68406b42d7725661da979b1403ec9926da205c6770827f33aac9d8f26e821"
$downloadUrl = "https://nodejs.org/dist/$version/$archiveName"
$runtimeDirectory = Join-Path $root "build\plugin_runtime"
$nodeExecutable = Join-Path $runtimeDirectory "node.exe"
$metadataFile = Join-Path $runtimeDirectory "runtime.json"
$temporaryRoot = Join-Path $env:TEMP "Pythia-Node-$version-x64"
$archivePath = Join-Path $temporaryRoot $archiveName
$extractPath = Join-Path $temporaryRoot "extract"

if ((Test-Path $nodeExecutable) -and (Test-Path $metadataFile)) {
    $metadata = Get-Content $metadataFile -Raw | ConvertFrom-Json
    if ($metadata.version -eq $version -and $metadata.architecture -eq "x64") {
        Write-Host "Pythia plugin runtime is already prepared: $nodeExecutable"
        exit 0
    }
}

Remove-Item $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
New-Item -ItemType Directory -Path $runtimeDirectory -Force | Out-Null

try {
    Invoke-WebRequest -Uri $downloadUrl -OutFile $archivePath
    $actualSha256 = (Get-FileHash -Algorithm SHA256 $archivePath).Hash.ToLowerInvariant()
    if ($actualSha256 -ne $expectedSha256) {
        throw "Node runtime checksum mismatch: expected $expectedSha256, got $actualSha256"
    }
    Expand-Archive -Path $archivePath -DestinationPath $extractPath -Force
    $source = Join-Path $extractPath "node-$version-win-x64\node.exe"
    if (-not (Test-Path $source)) {
        throw "Downloaded Node archive does not contain node.exe."
    }
    Copy-Item $source $nodeExecutable -Force
    @{
        version = $version
        architecture = "x64"
        source = $downloadUrl
        archiveSha256 = $expectedSha256
    } | ConvertTo-Json | Set-Content -Path $metadataFile -Encoding utf8
    Write-Host "Prepared Pythia plugin runtime: $nodeExecutable"
} finally {
    Remove-Item $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
}
