$ErrorActionPreference = "Stop"
$proyecto = "fulbito-svfc"
$firebaseBin = "C:\Home\Soft\Firebase\firebase.exe"

if (-not (Test-Path $firebaseBin)) {
    Write-Host "[ERROR] No se encontro firebase.exe en $firebaseBin" -ForegroundColor Red
    exit 1
}

# 1. Detectar version configurada en lib/main.dart
$mainContent = Get-Content "lib\main.dart" -Raw
$match = [regex]::Match($mainContent, "gAppVersion\s*=\s*'([^']+)'")
if (-not $match.Success) {
    Write-Host "[ERROR] No se pudo leer gAppVersion en lib/main.dart" -ForegroundColor Red
    exit 1
}
$version = $match.Groups[1].Value
$tag = "v$version"

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host " DESPLIEGUE AUTOMATICO FULBITO ($tag)" -ForegroundColor Cyan
Write-Host "=======================================================`n" -ForegroundColor Cyan

# 2. Compilar Web
Write-Host "1. Compilando Flutter Web..." -ForegroundColor Yellow
flutter build web --release
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Fallo la compilacion de Flutter." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Compilacion lista.`n" -ForegroundColor Green

# 3. Desplegar en Firebase Hosting
Write-Host "2. Desplegando en Firebase Hosting..." -ForegroundColor Yellow
& $firebaseBin use $proyecto
& $firebaseBin deploy --only hosting
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Fallo el deploy en Firebase." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Deploy en Firebase completado.`n" -ForegroundColor Green

# 4. Git Commit y Push con Tag para GitHub Actions
Write-Host "3. Subiendo cambios y activando GitHub Actions ($tag)..." -ForegroundColor Yellow
git add .

$cambios = git status --porcelain
if ($cambios) {
    git commit -m "release: $tag"
} else {
    Write-Host "Sin cambios de codigo para commitear." -ForegroundColor DarkGray
}

$branch = (git branch --show-current).Trim()
if (-not $branch) { $branch = "main" }

# Crear el tag si todavia no existe
$tagExiste = git tag -l $tag
if (-not $tagExiste) {
    Write-Host "Creando tag $tag..." -ForegroundColor DarkGray
    git tag -a $tag -m "release: $tag"
}

# Subir la rama y los tags
git push origin $branch --tags
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Fallo el push a GitHub." -ForegroundColor Red
    exit 1
}

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host " TODO DESPLEGADO Y RELEASE DISPARADA CON EXITO ($tag)" -ForegroundColor Cyan
Write-Host "=======================================================`n" -ForegroundColor Cyan