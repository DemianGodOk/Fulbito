$ErrorActionPreference = "Stop"
$proyecto = "fulbito-svfc"
$firebaseBin = "C:\Home\Soft\Firebase\firebase.exe"

if (-not (Test-Path $firebaseBin)) {
    Write-Host "[ERROR] No se encontro firebase.exe en $firebaseBin" -ForegroundColor Red
    exit 1
}

# 1. Leer y auto-incrementar la version en lib/main.dart
$mainPath = "lib\main.dart"
$mainContent = Get-Content $mainPath -Raw
$match = [regex]::Match($mainContent, "gAppVersion\s*=\s*'(\d+)\.(\d+)\.(\d+)'")
if (-not $match.Success) {
    Write-Host "[ERROR] No se encontro gAppVersion con formato X.Y.Z en $mainPath" -ForegroundColor Red
    exit 1
}

$major = [int]$match.Groups[1].Value
$minor = [int]$match.Groups[2].Value
$patch = [int]$match.Groups[3].Value + 1
$nuevaVersion = "$major.$minor.$patch"
$tag = "v$nuevaVersion"

$nuevoMain = [regex]::Replace($mainContent, "gAppVersion\s*=\s*'[^']+'", "gAppVersion = '$nuevaVersion'")
Set-Content $mainPath -Value $nuevoMain -NoNewline

# 2. Sincronizar pubspec.yaml automaticamente
$pubspecPath = "pubspec.yaml"
$pubspecContent = Get-Content $pubspecPath -Raw
$buildMatch = [regex]::Match($pubspecContent, "version:\s*[0-9\.]+\+?([0-9]*)")
$buildNum = 1
if ($buildMatch.Success -and $buildMatch.Groups[1].Value) {
    $buildNum = [int]$buildMatch.Groups[1].Value + 1
}
$nuevoPubspec = [regex]::Replace($pubspecContent, "version:\s*[^\r\n]+", "version: $nuevaVersion+$buildNum")
Set-Content $pubspecPath -Value $nuevoPubspec -NoNewline

# 3. Forzar headers no-cache en firebase.json
$firebaseConfig = @"
{
  "hosting": {
    "public": "build/web",
    "ignore": [
      "firebase.json",
      "**/.*",
      "**/node_modules/**"
    ],
    "headers": [
      {
        "source": "/**",
        "headers": [
          {
            "key": "Cache-Control",
            "value": "no-cache, no-store, must-revalidate"
          }
        ]
      }
    ]
  }
}
"@
Set-Content "firebase.json" -Value $firebaseConfig

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host " DESPLIEGUE AUTOMATICO: $tag (Build $buildNum)" -ForegroundColor Cyan
Write-Host "=======================================================`n" -ForegroundColor Cyan

# 4. Compilar Web
Write-Host "1. Compilando Flutter Web..." -ForegroundColor Yellow
flutter build web --release
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Fallo la compilacion de Flutter." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Compilacion lista.`n" -ForegroundColor Green

# 5. Desplegar en Firebase Hosting
Write-Host "2. Desplegando en Firebase Hosting..." -ForegroundColor Yellow
& $firebaseBin use $proyecto
& $firebaseBin deploy --only hosting
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Fallo el deploy en Firebase." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Deploy en Firebase completado.`n" -ForegroundColor Green

# 6. Git Commit, Tag y Push para GitHub Actions
Write-Host "3. Subiendo cambios y activando GitHub Actions ($tag)..." -ForegroundColor Yellow
git add .
git commit -m "release: $tag"

$branch = (git branch --show-current).Trim()
if (-not $branch) { $branch = "main" }

git tag -a $tag -m "release: $tag"
git push origin $branch --tags
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Fallo el push a GitHub." -ForegroundColor Red
    exit 1
}

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host " VERSION $tag PUBLICADA Y SUBIDA A GITHUB ACTIONS" -ForegroundColor Cyan
Write-Host "=======================================================`n" -ForegroundColor Cyan