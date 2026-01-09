#!/bin/bash
set -e

echo "========================================="
echo "  Тестирование webhook подписи"
echo "========================================="
echo ""

# Проверить что мы в правильной директории
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Файл docker-compose.yml не найден"
    echo "   Запустите скрипт из корневой директории проекта"
    exit 1
fi

# Загрузить переменные окружения
if [ -f ".env" ]; then
    # Более безопасный способ загрузки .env файла
    set -a  # Automatically export all variables
    source .env 2>/dev/null || {
        echo "⚠️  Ошибка при загрузке .env файла, продолжаем без него"
    }
    set +a
fi

API_URL="${API_URL:-https://linenarrow.com}"
API_KEY="${API_KEY}"
WEBHOOK_URL="${API_URL}/api/v1/webhook"

echo "API URL: ${API_URL}"
echo "Webhook URL: ${WEBHOOK_URL}"
echo ""

# Тест 1: Проверить public key загружен
echo "1. Проверка загрузки public key..."
echo "-----------------------------------"

# Проверить что файл существует
if [ -f "config/postal_public.key" ]; then
    echo "✓ Файл config/postal_public.key существует"
    
    # Проверить формат
    if head -1 config/postal_public.key | grep -q "BEGIN PUBLIC KEY"; then
        echo "✓ Формат ключа правильный (PEM)"
    else
        echo "⚠️  Формат ключа может быть неправильным"
        echo "   Ожидается: -----BEGIN PUBLIC KEY-----"
    fi
    
    # Проверить что ключ не пустой
    if [ -s config/postal_public.key ]; then
        key_lines=$(wc -l < config/postal_public.key)
        echo "✓ Ключ не пустой (${key_lines} строк)"
    else
        echo "❌ Ключ пустой!"
        exit 1
    fi
else
    echo "❌ Файл config/postal_public.key не найден"
    echo "   Запустите: ./scripts/get-postal-public-key.sh"
    exit 1
fi

# Проверить что API работает
echo ""
echo "2. Проверка доступности API..."
echo "-----------------------------------"

health_response=$(curl -s -k "${API_URL}/api/v1/health" 2>/dev/null || echo "")
if [ -z "$health_response" ]; then
    echo "❌ API недоступен по адресу ${API_URL}"
    exit 1
fi

# Извлечь health status (более надежный способ)
if command -v jq &> /dev/null; then
    health_status=$(echo "$health_response" | jq -r '.status' 2>/dev/null || echo "unknown")
else
    # Fallback без jq
    health_status=$(echo "$health_response" | grep -m1 '"status"' | sed 's/.*"status":"\([^"]*\)".*/\1/' 2>/dev/null || echo "unknown")
fi
echo "✓ API доступен (status: ${health_status})"

# Определить команду compose (поддержка старых версий)
DOCKER_COMPOSE=$(command -v docker-compose 2>/dev/null || echo "docker compose")

# Проверить что API контейнер запущен
if ! $DOCKER_COMPOSE ps | grep -q email_api.*Up; then
    echo "⚠️  API контейнер не запущен"
    echo "   Запустите: $DOCKER_COMPOSE up -d api"
else
    echo "✓ API контейнер запущен"
fi

# Проверить логи на наличие ошибок загрузки ключа
echo ""
echo "3. Проверка логов API на ошибки загрузки ключа..."
echo "-----------------------------------"

key_errors=$($DOCKER_COMPOSE logs api --tail=100 2>/dev/null | grep -i "public key\|signature" | tail -5 || echo "")
if [ -n "$key_errors" ]; then
    echo "Последние сообщения о ключе:"
    echo "$key_errors"
else
    echo "✓ Нет ошибок загрузки ключа в логах"
fi

# Тест 4: Отправить тестовый email (если API ключ доступен)
if [ -n "$API_KEY" ]; then
    echo ""
    echo "4. Тестовая отправка email (для генерации реального webhook)..."
    echo "-----------------------------------"
    
    test_response=$(curl -s -k -X POST \
      -H "Authorization: Bearer ${API_KEY}" \
      -H "Content-Type: application/json" \
      -d '{
        "recipient": "test@example.com",
        "from_name": "Webhook Test",
        "from_email": "noreply@linenarrow.com",
        "subject": "Webhook Signature Test",
        "variables": {},
        "template_id": "welcome",
        "tracking": {"campaign_id": "test_webhook", "message_id": "webhook_test_'$(date +%s)'"}
      }' \
      "${API_URL}/api/v1/send" 2>/dev/null || echo "")
    
    if [ -n "$test_response" ]; then
        status=$(echo "$test_response" | grep -o '"status":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
        echo "✓ Email поставлен в очередь (status: ${status})"
        echo "   Postal отправит webhook после доставки"
    else
        echo "⚠️  Не удалось отправить тестовый email"
    fi
else
    echo ""
    echo "4. Пропуск тестовой отправки (API_KEY не установлен)"
    echo "-----------------------------------"
    echo "   Установите API_KEY для полного тестирования"
fi

# Тест 5: Симулировать поддельный webhook
echo ""
echo "5. Тест с поддельной подписью (должен быть отклонен)..."
echo "-----------------------------------"

fake_payload='{
  "event": "MessageDelivered",
  "payload": {
    "message": {"id": "fake_msg_id_'$(date +%s)'"},
    "time": '$(date +%s)'
  }
}'

fake_response=$(curl -s -k -X POST \
  -H "Content-Type: application/json" \
  -H "X-Postal-Signature: fake_invalid_signature_base64_encoded" \
  -d "$fake_payload" \
  "${WEBHOOK_URL}" 2>/dev/null || echo "")

http_code=$(curl -s -k -o /dev/null -w "%{http_code}" -X POST \
  -H "Content-Type: application/json" \
  -H "X-Postal-Signature: fake_invalid_signature" \
  -d "$fake_payload" \
  "${WEBHOOK_URL}" 2>/dev/null || echo "000")

if [ "$http_code" = "401" ]; then
    echo "✓ Поддельный webhook правильно отклонен (401 Unauthorized)"
elif [ "$http_code" = "000" ]; then
    echo "⚠️  Не удалось подключиться к webhook endpoint"
else
    echo "⚠️  Неожиданный код ответа: ${http_code}"
    echo "   Ожидалось: 401 Unauthorized"
    echo "   Ответ: ${fake_response}"
fi

# Тест 6: Проверить логи после поддельного запроса
echo ""
echo "6. Проверка логов после поддельного запроса..."
echo "-----------------------------------"

sleep 1
recent_logs=$($DOCKER_COMPOSE logs api --tail=10 2>/dev/null | grep -i "signature\|webhook\|unauthorized" | tail -3 || echo "")
if [ -n "$recent_logs" ]; then
    echo "Последние сообщения о верификации:"
    echo "$recent_logs"
else
    echo "✓ Нет новых сообщений о верификации"
fi

# Итоговый отчет
echo ""
echo "========================================="
echo "  РЕЗУЛЬТАТЫ ТЕСТИРОВАНИЯ"
echo "========================================="
echo ""
echo "1. Public key файл: $( [ -f "config/postal_public.key" ] && echo "✓ Найден" || echo "❌ Не найден" )"
echo "2. API доступен: $( [ -n "$health_response" ] && echo "✓ Да" || echo "❌ Нет" )"
echo "3. Поддельный webhook: $( [ "$http_code" = "401" ] && echo "✓ Отклонен" || echo "⚠️  Неожиданный результат" )"
echo ""
echo "========================================="
echo "  СЛЕДУЮЩИЕ ШАГИ"
echo "========================================="
echo ""
echo "Если все тесты пройдены:"
echo "  1. Отправьте реальный email через API"
echo "  2. Проверьте логи API после получения webhook от Postal:"
echo "     docker compose logs api --tail=50 | grep -i 'signature\|webhook'"
echo ""
echo "Если есть проблемы:"
echo "  1. Проверьте формат public key (должен быть PEM)"
echo "  2. Убедитесь что ключ соответствует signing key в Postal"
echo "  3. Проверьте логи: docker compose logs api --tail=100"
echo ""
echo "Для отключения верификации (только для тестирования!):"
echo "  export SKIP_POSTAL_WEBHOOK_VERIFICATION=true"
echo "  docker compose restart api"
echo ""
