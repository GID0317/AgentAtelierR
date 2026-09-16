param(
    [string]$Device = "emulator-5554"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$keyFile = Join-Path $projectRoot ".asset_protection\character_assets.key"

Push-Location $projectRoot
try {
    & flutter pub get
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed." }
    & dart run tool/protect_character_assets.dart --key-file $keyFile
    if ($LASTEXITCODE -ne 0) { throw "Character asset protection failed." }
    $assetKey = (Get-Content -LiteralPath $keyFile -Raw).Trim()
    & flutter run -d $Device --no-pub "--dart-define=AAR_CHARACTER_ASSET_KEY=$assetKey"
    if ($LASTEXITCODE -ne 0) { throw "Protected Flutter run failed." }
}
finally {
    Pop-Location
}
