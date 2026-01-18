#!/bin/bash
set -e

cd /opt/email-sender

echo "==================================================================="
echo "ПРОВЕРКА WEBHOOK ЛОГОВ"
echo "==================================================================="
echo ""

echo "=== 1. Логи webhook запросов (последние 200 строк) ==="
echo "Ищем любые webhook события..."
docker compose logs --tail=200 api | grep -i "webhook\|MessageHeld\|MessageBounced\|MessageDelivered\|MessageSent" | tail -n 50 || echo "  (не найдено)"

echo ""
echo "=== 2. Логи обработки MessageHeld ==="
docker compose logs --tail=500 api | grep -i "MessageHeld" || echo "  (не найдено)"

echo ""
echo "=== 3. Логи DeliveryError ==="
docker compose logs --tail=500 api | grep -i "DeliveryError" || echo "  (не найдено)"

echo ""
echo "=== 4. Логи ошибок в API ==="
docker compose logs --tail=200 api | grep -i "error\|exception\|failed" | grep -v "HardFail\|MessageDeliveryFailed" | tail -n 30 || echo "  (не найдено)"

echo ""
echo "=== 5. Проверка - приходят ли webhook'и вообще? ==="
echo "Включим временно подробное логирование webhook'ов..."
echo ""

docker compose exec -T api bundle exec rails runner "
  # Проверим последние webhook запросы через логи Rails
  puts 'Проверка логов Rails за последние 24 часа...'
  puts 'Ищем упоминания postal_message_id, webhook, MessageHeld в логах...'
  puts ''
  puts 'Логи находятся в /app/log/production.log'
"

echo ""
echo "=== 6. Чтение production.log напрямую ==="
docker compose exec -T api tail -n 500 /app/log/production.log | grep -i "webhook\|MessageHeld\|MessageBounced\|postal_message_id" | tail -n 50 || echo "  (не найдено в production.log)"

echo ""
echo "=== 7. Проверка webhook endpoint ==="
echo "Webhook endpoint должен быть доступен по адресу:"
echo "POST https://linenarrow.com/api/v1/webhooks/postal"
echo ""

docker compose exec -T api bundle exec rails runner "
  puts 'Проверка маршрута webhook...'

  routes = Rails.application.routes.routes
  webhook_route = routes.find { |r| r.path.spec.to_s.include?('webhooks') && r.verb == 'POST' }

  if webhook_route
    puts '✅ Webhook маршрут найден:'
    puts \"  Path: #{webhook_route.path.spec}\"
    puts \"  Controller: #{webhook_route.defaults[:controller]}\"
    puts \"  Action: #{webhook_route.defaults[:action]}\"
  else
    puts '❌ Webhook маршрут НЕ найден!'
  end
"

echo ""
echo "==================================================================="
echo "ПРОВЕРКА ЗАВЕРШЕНА"
echo "==================================================================="
echo ""
