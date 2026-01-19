#!/bin/bash
# Скрипт для применения исправлений Postal на сервере
# Использование: bash deploy-postal-fix.sh

set -e

echo "=========================================="
echo "  Применение исправлений Postal"
echo "=========================================="
echo ""

# Перейти в директорию проекта
cd /opt/email-sender

# 1. Подтянуть изменения из git
echo "📥 Подтягивание изменений из git..."
git pull origin main

# 2. Проверить что postal.yml не монтируется
echo ""
echo "🔍 Проверка docker-compose.yml..."
if grep -q "postal.yml" docker-compose.yml; then
    echo "⚠️  ВНИМАНИЕ: postal.yml все еще монтируется в docker-compose.yml!"
    echo "   Нужно убрать строки с postal.yml из volumes"
    exit 1
else
    echo "✅ postal.yml не монтируется - хорошо!"
fi

# 3. Проверить что ENV переменные есть
echo ""
echo "🔍 Проверка ENV переменных..."
if [ ! -f .env ]; then
    echo "❌ Файл .env не найден!"
    exit 1
fi

REQUIRED_VARS=("MARIADB_PASSWORD" "RABBITMQ_PASSWORD" "SECRET_KEY_BASE" "DOMAIN")
MISSING_VARS=()

for var in "${REQUIRED_VARS[@]}"; do
    if ! grep -q "^${var}=" .env; then
        MISSING_VARS+=("$var")
    fi
done

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    echo "❌ Отсутствуют переменные в .env:"
    for var in "${MISSING_VARS[@]}"; do
        echo "   - $var"
    done
    exit 1
else
    echo "✅ Все необходимые переменные есть в .env"
fi

# 4. Перезапустить Postal
echo ""
echo "🔄 Перезапуск Postal..."
docker compose restart postal

# 5. Подождать запуска
echo "⏳ Ожидание запуска Postal (10 секунд)..."
sleep 10

# 6. Проверить логи
echo ""
echo "📋 Проверка логов Postal..."
echo "Последние 30 строк логов:"
docker compose logs postal --tail=30

echo ""
echo "🔍 Поиск ошибок подключения к БД..."
ERRORS=$(docker compose logs postal --tail=50 | grep -i "error\|denied\|mysql" || true)

if [ -z "$ERRORS" ]; then
    echo "✅ Ошибок подключения к БД не найдено!"
else
    echo "⚠️  Найдены возможные ошибки:"
    echo "$ERRORS"
fi

# 7. Проверить что Postal использует ENV переменные
echo ""
echo "🔍 Проверка ENV переменных в контейнере..."
if docker compose exec -T postal env | grep -q "POSTAL_MAIN_DB_PASSWORD="; then
    DB_PASS=$(docker compose exec -T postal env | grep "POSTAL_MAIN_DB_PASSWORD=" | cut -d= -f2)
    if [ -z "$DB_PASS" ] || [ "$DB_PASS" = "\${MARIADB_PASSWORD}" ]; then
        echo "❌ POSTAL_MAIN_DB_PASSWORD не подставлен правильно!"
        exit 1
    else
        echo "✅ POSTAL_MAIN_DB_PASSWORD подставлен (значение скрыто)"
    fi
else
    echo "❌ POSTAL_MAIN_DB_PASSWORD не найден в контейнере!"
    exit 1
fi

# 8. Проверить что файл postal.yml не используется
echo ""
echo "🔍 Проверка что postal.yml не монтируется..."
if docker compose exec -T postal test -f /opt/postal/config/postal.yml 2>/dev/null; then
    echo "⚠️  Файл /opt/postal/config/postal.yml существует!"
    echo "   Это может означать что он все еще монтируется"
else
    echo "✅ Файл postal.yml не монтируется - хорошо!"
fi

echo ""
echo "=========================================="
echo "✅ Исправления применены!"
echo "=========================================="
echo ""
echo "📋 Следующие шаги:"
echo "1. Проверьте веб-интерфейс Postal:"
echo "   - Прямой доступ: http://your-server-ip:5000"
echo "   - Через nginx: https://your-domain/postal/"
echo ""
echo "2. Войдите с учетными данными"
echo ""
echo "3. Проверьте что страницы после входа загружаются"
echo ""
echo "4. Если есть проблемы, проверьте логи:"
echo "   docker compose logs postal --tail=50"
