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
    
    $content = $content -replace 'version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)', "version: $newVersionFull"
    [IO.File]::WriteAllText($pubspecPath, $content)
    Write-Host ">> Version incrementada a $newVersionFull" -ForegroundColor Green
} else {
    Write-Host "Error: No se encontro el formato de version en pubspec.yaml" -ForegroundColor Red
    exit 1
}

# 2. Actualizar kAppVersion en lib/main.dart
if (Test-Path $mainPath) {
    $mainContent = Get-Content $mainPath -Raw
    $mainContent = $mainContent -replace "const String kAppVersion = '.*?';", "const String kAppVersion = '$newVersion';"
    [IO.File]::WriteAllText($mainPath, $mainContent)
    Write-Host ">> kAppVersion actualizada a '$newVersion' en main.dart" -ForegroundColor Green
}

# 3. Guardar todo en Git y enviar a GitHub
Write-Host ">> Enviando cambios a GitHub..." -ForegroundColor Cyan
git add .
git commit -m "release: v$newVersion"
git push origin main

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Yellow
Write-Host " LISTO: Version v$newVersion enviada." -ForegroundColor Yellow
Write-Host " GitHub Actions esta compilando el APK y publicando el release." -ForegroundColor Yellow
Write-Host " En 3 minutos abris la app en el celular y te avisa sola." -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Yellow
