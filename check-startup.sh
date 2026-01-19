#!/bin/bash
# Скрипт для проверки запуска контейнеров после исправления

echo "=== Проверка Запуска Контейнеров ==="
echo ""

echo "Ожидание 30 секунд для полного запуска..."
sleep 30

echo ""
echo "=== Статус Контейнеров ==="
docker compose ps

echo ""
echo "=== Логи API (последние 30 строк) ==="
docker compose logs api --tail=30

echo ""
echo "=== Проверка Ошибок в Логах ==="
ERROR_COUNT=$(docker compose logs api --tail=100 | grep -i "error\|exception\|failed" | wc -l)
if [ $ERROR_COUNT -eq 0 ]; then
  echo "✅ Ошибок не найдено в логах API"
else
  echo "⚠️  Найдено $ERROR_COUNT строк с ошибками в логах:"
  docker compose logs api --tail=100 | grep -i "error\|exception\|failed" | tail -10
fi

echo ""
echo "=== Проверка Загрузки Моделей ==="
docker compose exec api rails runner "
begin
  puts 'EmailClick count: ' + EmailClick.count.to_s
  puts 'EmailOpen count: ' + EmailOpen.count.to_s
  puts '✅ Модели загружены успешно!'
rescue => e
  puts '❌ Ошибка при загрузке моделей:'
  puts e.message
  exit 1
end
" 2>&1

echo ""
echo "=== Проверка Доступности Dashboard ==="
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 2>&1 || echo "000")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "302" ]; then
  echo "✅ API отвечает (HTTP $HTTP_CODE)"
else
  echo "❌ API не отвечает (HTTP $HTTP_CODE)"
fi

echo ""
echo "=== Итоговый Статус ==="
API_STATUS=$(docker compose ps api --format "{{.Status}}" | grep -o "healthy\|unhealthy\|starting" || echo "unknown")
SIDEKIQ_STATUS=$(docker compose ps sidekiq --format "{{.Status}}" | grep -o "healthy\|unhealthy\|starting" || echo "unknown")

if [ "$API_STATUS" = "healthy" ] && [ "$SIDEKIQ_STATUS" = "healthy" ]; then
  echo "✅ API: $API_STATUS"
  echo "✅ Sidekiq: $SIDEKIQ_STATUS"
  echo ""
  echo "🎉 Система запущена успешно!"
  echo ""
  echo "Проверьте дашборд в браузере: https://linenarrow.com"
else
  echo "⚠️  API: $API_STATUS"
  echo "⚠️  Sidekiq: $SIDEKIQ_STATUS"
  echo ""
  echo "Контейнеры всё ещё запускаются или есть проблемы."
  echo "Подождите ещё 30 секунд и запустите скрипт снова."
fi
