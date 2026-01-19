# Скрипт для исправления postal.yml - подстановка переменных окружения
# Использование: .\fix-postal-config.ps1

Write-Host "🔧 Исправление postal.yml..." -ForegroundColor Cyan

# Проверка что .env существует
if (-not (Test-Path ".env")) {
    Write-Host "❌ Файл .env не найден!" -ForegroundColor Red
    Write-Host "Создайте .env файл или запустите scripts/pre-install.sh" -ForegroundColor Yellow
    exit 1
}

# Проверка что postal.yml.example существует
if (-not (Test-Path "config/postal.yml.example")) {
    Write-Host "❌ Файл config/postal.yml.example не найден!" -ForegroundColor Red
    exit 1
}

# Создать backup
if (Test-Path "config/postal.yml") {
    $backupName = "config/postal.yml.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item "config/postal.yml" $backupName
    Write-Host "✅ Создан backup: $backupName" -ForegroundColor Green
}

# Загрузить переменные из .env
Write-Host "📖 Загрузка переменных из .env..." -ForegroundColor Cyan
$envVars = @{}
Get-Content ".env" | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
        $key = $matches[1].Trim()
        $value = $matches[2].Trim()
        # Убрать кавычки если есть
        $value = $value -replace '^["'']|["'']$', ''
        $envVars[$key] = $value
    }
}

# Проверить что нужные переменные есть
$requiredVars = @('MARIADB_PASSWORD', 'RABBITMQ_PASSWORD', 'SECRET_KEY_BASE', 'DOMAIN')
$missingVars = @()
foreach ($var in $requiredVars) {
    if (-not $envVars.ContainsKey($var) -or [string]::IsNullOrWhiteSpace($envVars[$var])) {
        $missingVars += $var
    }
}

if ($missingVars.Count -gt 0) {
    Write-Host "❌ Отсутствуют переменные в .env:" -ForegroundColor Red
    $missingVars | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    exit 1
}

# Читать postal.yml.example и подставить переменные
Write-Host "📝 Подстановка переменных..." -ForegroundColor Cyan
$content = Get-Content "config/postal.yml.example" -Raw

# Подставить каждую переменную
foreach ($key in $envVars.Keys) {
    $pattern = '\$\{' + [regex]::Escape($key) + '\}'
    $content = $content -replace $pattern, $envVars[$key]
}

# Сохранить результат
$content | Out-File "config/postal.yml" -Encoding UTF8 -NoNewline
Write-Host "✅ Создан config/postal.yml" -ForegroundColor Green

# Проверить что переменные подставились
Write-Host "`n🔍 Проверка результата..." -ForegroundColor Cyan
$checkContent = Get-Content "config/postal.yml" -Raw

$hasUnsubstituted = $false
foreach ($var in $requiredVars) {
    if ($checkContent -match '\$\{' + [regex]::Escape($var) + '\}') {
        Write-Host "  ⚠️  ${var} не подставлен!" -ForegroundColor Yellow
        $hasUnsubstituted = $true
    }
}

if (-not $hasUnsubstituted) {
    Write-Host "✅ Все переменные подставлены!" -ForegroundColor Green
    
    # Показать примеры (без паролей)
    Write-Host "`n📋 Примеры подставленных значений:" -ForegroundColor Cyan
    $checkContent -split "`n" | Select-String -Pattern "password:|secret_key:" | Select-Object -First 3 | ForEach-Object {
        $line = $_.Line
        # Скрыть пароли
        $line = $line -replace '(password:\s*)(.+)$', '$1***'
        $line = $line -replace '(secret_key:\s*)(.+)$', '$1***'
        Write-Host "  $line" -ForegroundColor Gray
    }
} else {
    Write-Host "❌ Некоторые переменные не подставлены!" -ForegroundColor Red
    exit 1
}

Write-Host "`n✅ Готово! Теперь перезапустите Postal:" -ForegroundColor Green
Write-Host "   docker compose restart postal" -ForegroundColor Cyan
