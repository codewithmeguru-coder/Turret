# Builds the Android app, copies it to Turret.apk here, then deletes the
# build folders (mobile\build and mobile\.dart_tool) so they don't pile up.
# Run from this folder:  .\build_apk.ps1
$ErrorActionPreference = 'Stop'
Push-Location "$PSScriptRoot\mobile"
try {
    flutter build apk --release
    if ($LASTEXITCODE -ne 0) { throw 'The build failed.' }
    Copy-Item 'build\app\outputs\flutter-apk\app-release.apk' "$PSScriptRoot\Turret.apk" -Force
    flutter clean | Out-Null
    Write-Host "Done: $PSScriptRoot\Turret.apk"
} finally {
    Pop-Location
}
