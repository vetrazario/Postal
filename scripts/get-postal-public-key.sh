#!/bin/bash
set -e

echo "============================================="
echo "  Получение Public Key из Postal"
echo "============================================="
echo ""

# Определить команду compose (поддержка старых версий)
DOCKER_COMPOSE=$(command -v docker-compose 2>/dev/null || echo "docker compose")

# Проверить что Postal запущен
if ! $DOCKER_COMPOSE ps | grep -q email_postal.*Up; then
    echo "❌ Postal не запущен"
    echo "   Запустите: $DOCKER_COMPOSE up -d postal"
    exit 1
fi

echo "✓ Postal запущен"
echo ""

# Проверить что мы в правильной директории
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Файл docker-compose.yml не найден"
    echo "   Запустите скрипт из корневой директории проекта"
    exit 1
fi

# Проверить наличие POSTAL_API_KEY
if [ -z "$POSTAL_API_KEY" ]; then
    echo "⚠️  POSTAL_API_KEY не установлен в окружении"
    echo "   Попытка загрузить из .env файла..."
    
    if [ -f ".env" ]; then
        # Более безопасный способ загрузки .env файла
        set -a  # Automatically export all variables
        source .env 2>/dev/null || {
            echo "❌ Ошибка при загрузке .env файла"
            exit 1
        }
        set +a
    else
        echo "❌ Файл .env не найден"
        echo "   Установите POSTAL_API_KEY вручную:"
        echo "   export POSTAL_API_KEY='your-api-key'"
        exit 1
    fi
fi

if [ -z "$POSTAL_API_KEY" ]; then
    echo "❌ POSTAL_API_KEY не найден"
    echo ""
    echo "   Получите API ключ из Postal Web UI:"
    echo "   1. Откройте https://linenarrow.com/postal/"
    echo "   2. Перейдите в Organization → Server → API Keys"
    echo "   3. Создайте новый API ключ или используйте существующий"
    echo "   4. Установите: export POSTAL_API_KEY='your-key'"
    exit 1
fi

echo "✓ POSTAL_API_KEY найден"
echo ""

# Получить organization и server из Postal
# Postal API требует organization_id и server_id
# Для упрощения, попробуем получить их автоматически

echo "Получение информации о сервере Postal..."
echo ""

# Попробовать получить список серверов через Postal API
# Формат: POST /api/v1/servers
# Используем $POSTAL_API_KEY без фигурных скобок для безопасности
response=$(curl -s -X GET \
  -H "X-Server-API-Key: $POSTAL_API_KEY" \
  "http://postal:5000/api/v1/servers" 2>/dev/null || echo "")

if [ -z "$response" ] || echo "$response" | grep -q "error\|unauthorized"; then
    echo "⚠️  Не удалось получить информацию через API"
    echo ""
    echo "   ВАРИАНТ 1: Получить public key вручную через Postal Web UI"
    echo "   ============================================="
    echo "   1. Откройте: https://linenarrow.com/postal/"
    echo "   2. Перейдите в: Organization → Server → Credentials"
    echo "   3. Найдите 'Webhook Credentials' или создайте новые"
    echo "   4. Скопируйте 'Public Key' (PEM формат)"
    echo "   5. Сохраните в файл:"
    echo ""
    echo "      cat > config/postal_public.key << 'EOF'"
    echo "      -----BEGIN PUBLIC KEY-----"
    echo "      (вставьте скопированный ключ)"
    echo "      -----END PUBLIC KEY-----"
    echo "      EOF"
    echo ""
    echo "   6. Установите права: chmod 644 config/postal_public.key"
    echo ""
    echo "   ВАРИАНТ 2: Использовать Postal CLI"
    echo "   ============================================="
    echo "   docker compose exec postal postal make-webhook-credential"
    echo "   # Это создаст новый ключ pair"
    echo "   # Скопируйте public key из вывода"
    echo ""
    exit 1
fi

# Если API работает, попробовать получить webhook credentials
echo "Попытка получить webhook credentials через API..."
echo ""

# Postal API для webhook credentials может требовать server_id
# Для упрощения, создадим инструкцию

echo "============================================="
echo "  ИНСТРУКЦИЯ ПО ПОЛУЧЕНИЮ PUBLIC KEY"
echo "============================================="
echo ""
echo "Postal использует RSA ключи для подписи webhook'ов."
echo "Public key нужно получить из Postal Web UI или CLI."
echo ""
echo "СПОСОБ 1: Через Postal Web UI (РЕКОМЕНДУЕТСЯ)"
echo "---------------------------------------------"
echo "1. Откройте Postal Web UI:"
echo "   https://linenarrow.com/postal/"
echo ""
echo "2. Войдите в систему"
echo ""
echo "3. Перейдите:"
echo "   Organization → Server → Credentials"
echo ""
echo "4. Найдите раздел 'Webhook Credentials'"
echo "   Если его нет, создайте новый credential:"
echo "   - Type: Webhook"
echo "   - Name: Webhook Signing Key"
echo ""
echo "5. Скопируйте 'Public Key' (PEM формат)"
echo "   Он начинается с: -----BEGIN PUBLIC KEY-----"
echo ""
echo "6. Сохраните в файл на сервере:"
echo ""
echo "   cd /opt/email-sender"
echo "   cat > config/postal_public.key << 'EOF'"
echo "   -----BEGIN PUBLIC KEY-----"
echo "   (вставьте скопированный ключ)"
echo "   -----END PUBLIC KEY-----"
echo "   EOF"
echo "   chmod 644 config/postal_public.key"
echo ""
echo "СПОСОБ 2: Через Postal CLI"
echo "---------------------------------------------"
echo "docker compose exec postal postal make-webhook-credential"
echo ""
echo "Это создаст новый ключ pair и покажет public key."
echo "Скопируйте public key и сохраните в config/postal_public.key"
echo ""
echo "СПОСОБ 3: Если ключ уже существует"
echo "---------------------------------------------"
echo "Если у вас уже есть private key, можно извлечь public:"
echo ""
echo "   # Если у вас есть private key в PEM формате:"
echo "   openssl rsa -in private_key.pem -pubout -out config/postal_public.key"
echo ""
echo "============================================="
echo ""

# Проверить, существует ли уже файл
if [ -f "config/postal_public.key" ]; then
    echo "⚠️  Файл config/postal_public.key уже существует"
    echo ""
    read -p "Перезаписать? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Отменено. Используйте существующий файл."
        exit 0
    fi
fi

# Если пользователь хочет создать тестовый ключ
echo ""
read -p "Создать тестовый ключ pair для разработки? (y/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "⚠️  ВНИМАНИЕ: Это ТЕСТОВЫЙ ключ!"
    echo "   Он НЕ будет работать с реальными webhook'ами от Postal!"
    echo "   Используйте только для разработки и тестирования!"
    echo ""
    
    # Создать директорию если не существует
    mkdir -p config
    
    # Генерировать тестовый ключ pair
    openssl genrsa -out config/test_postal_private_key.pem 2048 2>/dev/null
    openssl rsa -in config/test_postal_private_key.pem -pubout -out config/postal_public.key 2>/dev/null
    
    chmod 644 config/postal_public.key
    chmod 600 config/test_postal_private_key.pem
    
    echo "✓ Тестовый ключ создан:"
    echo "   Private: config/test_postal_private_key.pem"
    echo "   Public:  config/postal_public.key"
    echo ""
    echo "⚠️  Для PRODUCTION нужно получить реальный public key из Postal!"
    echo ""
    exit 0
fi

echo ""
echo "Для получения реального public key следуйте инструкциям выше."
echo "После получения ключа, сохраните его в config/postal_public.key"
echo ""
