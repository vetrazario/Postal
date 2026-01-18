#!/bin/bash
set -e

cd /opt/email-sender

echo "==================================================================="
echo "ПРОВЕРКА ВЕРСИИ КОДА В КОНТЕЙНЕРЕ API"
echo "==================================================================="
echo ""

echo "=== 1. Когда был собран образ API? ==="
docker compose images api

echo ""
echo "=== 2. Есть ли в контейнере код создания DeliveryError? ==="
docker compose exec -T api bash -c "grep -n 'DeliveryError created for MessageHeld' app/controllers/api/v1/webhooks_controller.rb" || echo "❌ КОД НЕ НАЙДЕН В КОНТЕЙНЕРЕ!"

echo ""
echo "=== 3. Версия кода на хосте ==="
grep -n "DeliveryError created for MessageHeld" services/api/app/controllers/api/v1/webhooks_controller.rb || echo "❌ КОД НЕ НАЙДЕН НА ХОСТЕ!"

echo ""
echo "=== 4. Последний git commit ==="
git log --oneline -5

echo ""
echo "=== 5. Когда был последний restart API? ==="
docker compose ps api

echo ""
echo "==================================================================="
echo "РЕКОМЕНДАЦИЯ"
echo "==================================================================="
echo ""
echo "Если код НЕ НАЙДЕН в контейнере, нужно:"
echo "1. docker compose stop api"
echo "2. docker compose rm -f api"
echo "3. docker compose build --no-cache api"
echo "4. docker compose up -d"
echo ""
