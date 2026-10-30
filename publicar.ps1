$pubspecPath = "pubspec.yaml"
$mainPath = "lib/main.dart"

# 1. Leer y subir versión en pubspec.yaml
$content = Get-Content $pubspecPath -Raw
if ($content -match 'version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)') {
    $major = $matches[1]
    $minor = $matches[2]
    $patch = [int]$matches[3] + 1
    $build = [int]$matches[4] + 1
    $newVersion = "$major.$minor.$patch"
    $newVersionFull = "$newVersion+$build"
    
    $content = $content -replace 'version:\s*(\d+)\.(\d+)\+(\d+)', "version: $newVersionFull"
    [IO.File]::WriteAllText($pubspecPath, $content)
    Write-Host ">> Version incrementada a $newVersionFull" -ForegroundColor Green
} else {
    Write-Host "Error: No se encontro el patron de version en pubspec.yaml" -ForegroundColor Red
    exit 1
}

# 2. Sincronizar kAppVersion en main.dart
if (Test-Path $mainPath) {
    $mainContent = Get-Content $mainPath -Raw
    $mainContent = $mainContent -replace "const String kAppVersion = '.*?';", "const String kAppVersion = '$newVersion';"
    [IO.File]::WriteAllText($mainPath, $mainContent)
    Write-Host ">> kAppVersion actualizada a '$newVersion' en main.dart" -ForegroundColor Green
}

# 3. Guardar, crear tag y enviar todo junto
Write-Host ">> Empaquetando commit y tag v$newVersion..." -ForegroundColor Cyan
git add .
git commit -m "release: v$newVersion"
git tag -a "v$newVersion" -m "Release v$newVersion"

Write-Host ">> Subiendo a GitHub..." -ForegroundColor Cyan
git push origin main
git push origin "v$newVersion"

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Yellow
Write-Host " LISTO: Tag v$newVersion enviado a GitHub." -ForegroundColor Yellow
Write-Host " GitHub Actions tomo el tag y empezo a compilar el APK." -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Yellow
