# ===========================================
# Проверка зависимостей для развертывания
# ===========================================

Write-Host "=========================================="
Write-Host "Проверка зависимостей"
Write-Host "=========================================="
Write-Host ""

$allOk = $true

# Проверка Docker
Write-Host "Проверка Docker..."
try {
    $dockerVersion = docker --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✅ Docker установлен: $dockerVersion" -ForegroundColor Green
    } else {
        throw "Docker not found"
    }
} catch {
    Write-Host "  ❌ Docker не установлен" -ForegroundColor Red
    Write-Host "     Установите Docker Desktop: https://www.docker.com/products/docker-desktop" -ForegroundColor Yellow
    $allOk = $false
}

# Проверка Docker Compose
Write-Host "Проверка Docker Compose..."
try {
    $composeVersion = docker compose version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✅ Docker Compose установлен: $composeVersion" -ForegroundColor Green
    } else {
        throw "Docker Compose not found"
    }
} catch {
    Write-Host "  ❌ Docker Compose не установлен" -ForegroundColor Red
    $allOk = $false
}

# Проверка Docker запущен
Write-Host "Проверка Docker daemon..."
try {
    docker info 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✅ Docker daemon запущен" -ForegroundColor Green
    } else {
        throw "Docker daemon not running"
    }
} catch {
    Write-Host "  ❌ Docker daemon не запущен" -ForegroundColor Red
    Write-Host "     Запустите Docker Desktop" -ForegroundColor Yellow
    $allOk = $false
}

Write-Host ""
Write-Host "Проверка файлов конфигурации..."

# Проверка .env
if (Test-Path .env) {
    Write-Host "  ✅ .env файл существует" -ForegroundColor Green
} else {
    Write-Host "  ⚠️  .env файл не найден" -ForegroundColor Yellow
    Write-Host "     Создайте из env.example.txt" -ForegroundColor Yellow
}

# Проверка nginx.conf
if (Test-Path config/nginx.conf) {
    Write-Host "  ✅ config/nginx.conf существует" -ForegroundColor Green
} else {
    Write-Host "  ⚠️  config/nginx.conf не найден" -ForegroundColor Yellow
}

# Проверка postal.yml
if (Test-Path config/postal.yml) {
    Write-Host "  ✅ config/postal.yml существует" -ForegroundColor Green
} else {
    Write-Host "  ⚠️  config/postal.yml не найден" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=========================================="
if ($allOk) {
    Write-Host "✅ Все зависимости установлены!" -ForegroundColor Green
    Write-Host "   Можно запускать: docker compose up -d" -ForegroundColor Green
} else {
    Write-Host "❌ Некоторые зависимости отсутствуют" -ForegroundColor Red
    Write-Host "   Установите недостающие компоненты и повторите проверку" -ForegroundColor Yellow
}
Write-Host "=========================================="

exit ($allOk ? 0 : 1)





