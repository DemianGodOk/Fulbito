# ============================================================================
# SCRIPT DE DESPLIEGUE AUTOMÁTICO DE FULBITO
# ============================================================================
$ErrorActionPreference = "Stop"
$proyecto = "fulbito-svfc"
$firebaseBin = "C:\Home\Soft\Firebase\firebase.exe"

# 1. Validar que exista el ejecutable de Firebase
if (-not (Test-Path $firebaseBin)) {
    Write-Host "[ERROR] No se encontró firebase.exe en $firebaseBin" -ForegroundColor Red
    exit 1
}

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host " INICIANDO DESPLIEGUE AUTOMÁTICO" -ForegroundColor Cyan
Write-Host "=======================================================`n" -ForegroundColor Cyan

# 2. Compilar Web
Write-Host "1. Compilando Flutter Web..." -ForegroundColor Yellow
flutter build web --release
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Falló la compilación de Flutter." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Compilación lista.`n" -ForegroundColor Green

# 3. Desplegar en Firebase Hosting
Write-Host "2. Desplegando en Firebase Hosting..." -ForegroundColor Yellow
& $firebaseBin use $proyecto
& $firebaseBin deploy --only hosting
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Falló el deploy en Firebase." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Deploy en Firebase completado.`n" -ForegroundColor Green

# 4. Git Commit & Push
Write-Host "3. Subiendo cambios a GitHub..." -ForegroundColor Yellow
$commitMensaje = Read-Host "Mensaje para el commit (Enter para 'Actualización automática')"
if ([string]::IsNullOrWhiteSpace($commitMensaje)) {
    $commitMensaje = "Actualización automática y deploy"
}

git add .
$cambios = git status --porcelain
if ($cambios) {
    git commit -m "$commitMensaje"
} else {
    Write-Host "Sin cambios locales para commitear." -ForegroundColor DarkGray
}

$branch = (git branch --show-current).Trim()
if (-not $branch) { $branch = "main" }

git push origin $branch
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Falló el push a GitHub." -ForegroundColor Red
    exit 1
}

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host " TODO DESPLEGADO Y SUBIDO CON ÉXITO" -ForegroundColor Cyan
Write-Host "=======================================================`n" -ForegroundColor Cyan