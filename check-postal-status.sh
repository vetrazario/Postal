#!/bin/bash
# Скрипт для проверки статуса Postal после исправлений

echo "=========================================="
echo "  Проверка статуса Postal"
echo "=========================================="
echo ""

cd /opt/email-sender

# 1. Проверить что postal.yml убран из docker-compose.yml
echo "1️⃣ Проверка docker-compose.yml..."
if grep -q "postal.yml" docker-compose.yml; then
    echo "   ❌ postal.yml все еще монтируется!"
    echo "   Нужно запустить: bash fix-docker-compose.sh"
else
    echo "   ✅ postal.yml не монтируется - хорошо!"
fi

# 2. Проверить что файл не существует в контейнере
echo ""
echo "2️⃣ Проверка файла в контейнере..."
if docker compose exec -T postal test -f /opt/postal/config/postal.yml 2>/dev/null; then
    echo "   ⚠️  Файл /opt/postal/config/postal.yml существует!"
    echo "   Это может означать что он все еще монтируется"
else
    echo "   ✅ Файл postal.yml не существует в контейнере - хорошо!"
fi

# 3. Проверить ENV переменные
echo ""
echo "3️⃣ Проверка ENV переменных..."
if docker compose exec -T postal env | grep -q "POSTAL_MAIN_DB_PASSWORD="; then
    DB_PASS=$(docker compose exec -T postal env | grep "POSTAL_MAIN_DB_PASSWORD=" | cut -d= -f2)
    if [ -z "$DB_PASS" ] || [ "$DB_PASS" = "\${MARIADB_PASSWORD}" ]; then
        echo "   ❌ POSTAL_MAIN_DB_PASSWORD не подставлен правильно!"
    else
        echo "   ✅ POSTAL_MAIN_DB_PASSWORD подставлен (значение скрыто)"
    fi
else
    echo "   ❌ POSTAL_MAIN_DB_PASSWORD не найден!"
fi

# 4. Проверить статус контейнера
echo ""
echo "4️⃣ Статус контейнера Postal..."
docker compose ps postal

# 5. Проверить логи на ошибки
echo ""
echo "5️⃣ Проверка логов (последние 30 строк)..."
docker compose logs postal --tail=30

echo ""
echo "6️⃣ Поиск ошибок подключения к БД..."
ERRORS=$(docker compose logs postal --tail=50 | grep -i "error\|denied\|mysql\|can't connect" || true)

if [ -z "$ERRORS" ]; then
    echo "   ✅ Ошибок подключения к БД не найдено!"
else
    echo "   ⚠️  Найдены возможные ошибки:"
    echo "$ERRORS" | head -10
fi

# 6. Проверить доступность веб-интерфейса
echo ""
echo "7️⃣ Проверка веб-интерфейса..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5000 || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    echo "   ✅ Веб-интерфейс доступен (HTTP $HTTP_CODE)"
else
    echo "   ⚠️  Веб-интерфейс недоступен (HTTP $HTTP_CODE)"
fi

echo ""
echo "=========================================="
echo "✅ Проверка завершена"
echo "=========================================="
