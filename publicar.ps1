$ErrorActionPreference = "Stop"
$proyecto = "fulbito-svfc"
$cuentaFirebase = "demian.soriano@gmail.com"
$firebaseBin = "C:\Home\Soft\Firebase\firebase.exe"

if (-not (Test-Path $firebaseBin)) {
    Write-Host "[ERROR] No se encontro firebase.exe en $firebaseBin" -ForegroundColor Red
    exit 1
}

# 1. Leer y auto-incrementar la version en lib/constants.dart
$constantsPath = "lib\constants.dart"
$constantsContent = Get-Content $constantsPath -Raw
$match = [regex]::Match($constantsContent, "gAppVersion\s*=\s*'(\d+)\.(\d+)\.(\d+)'")
if (-not $match.Success) {
    Write-Host "[ERROR] No se encontro gAppVersion con formato X.Y.Z en $constantsPath" -ForegroundColor Red
    exit 1
}

$major = [int]$match.Groups[1].Value
$minor = [int]$match.Groups[2].Value
$patch = [int]$match.Groups[3].Value + 1
$nuevaVersion = "$major.$minor.$patch"
$tag = "v$nuevaVersion"

$nuevoConstants = [regex]::Replace($constantsContent, "gAppVersion\s*=\s*'[^']+'", "gAppVersion = '$nuevaVersion'")
Set-Content $constantsPath -Value $nuevoConstants -NoNewline

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

# 4. Aislar credenciales de Git y subir primero para activar GitHub Actions en paralelo
Write-Host "1. Subiendo cambios y activando GitHub Actions ($tag)..." -ForegroundColor Yellow
git config --local credential.useHttpPath true
git config --local user.email $cuentaFirebase

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
Write-Host "[OK] Push a GitHub completado. GitHub Actions ya esta compilando.`n" -ForegroundColor Green

# 5. Compilar Web
Write-Host "2. Compilando Flutter Web..." -ForegroundColor Yellow
flutter build web --release
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Fallo la compilacion de Flutter." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Compilacion lista.`n" -ForegroundColor Green

# 6. Desplegar en Firebase Hosting con cuenta fija
Write-Host "3. Desplegando en Firebase Hosting..." -ForegroundColor Yellow
& $firebaseBin deploy --only hosting --project $proyecto --account $cuentaFirebase
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Fallo el deploy en Firebase." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Deploy en Firebase completado.`n" -ForegroundColor Green

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host " VERSION $tag SUBIDA A GITHUB ACTIONS Y PUBLICADA EN WEB" -ForegroundColor Cyan
Write-Host "=======================================================`n" -ForegroundColor Cyan
