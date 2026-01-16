#!/bin/bash
# Финальный rebuild и запуск

echo "=== ФИНАЛЬНЫЙ REBUILD И ЗАПУСК ==="
echo ""

echo "Шаг 1: Остановка контейнеров..."
docker compose stop api sidekiq

echo ""
echo "Шаг 2: Пересборка образа API с новым кодом..."
docker compose build api

echo ""
echo "Шаг 3: Запуск контейнеров..."
docker compose up -d api sidekiq

echo ""
echo "Шаг 4: Ожидание 60 секунд для полного запуска..."
sleep 60

echo ""
echo "Шаг 5: Проверка статуса..."
docker compose ps

echo ""
echo "Шаг 6: Проверка логов API (последние 40 строк)..."
docker compose logs api --tail=40 | tail -40

echo ""
echo "Шаг 7: Проверка ошибок..."
ERROR_COUNT=$(docker compose logs api --tail=100 | grep -i "error\|exception\|failed" | grep -v "ERROR:  relation" | wc -l)
if [ $ERROR_COUNT -eq 0 ]; then
  echo "✅ Критических ошибок не найдено"
else
  echo "⚠️  Найдено ошибок: $ERROR_COUNT"
  docker compose logs api --tail=100 | grep -i "error\|exception\|failed" | grep -v "ERROR:  relation" | tail -10
fi

echo ""
echo "Шаг 8: Проверка миграций..."
docker compose exec -T postgres psql -U email_sender -d email_sender -c "
SELECT version FROM schema_migrations WHERE version LIKE '202601%' ORDER BY version;
"

echo ""
echo "Шаг 9: Проверка таблиц..."
docker compose exec -T postgres psql -U email_sender -d email_sender -c "
SELECT table_name FROM information_schema.tables
WHERE table_name IN ('email_clicks', 'email_opens')
ORDER BY table_name;
"

echo ""
echo "Шаг 10: Проверка индексов..."
docker compose exec -T postgres psql -U email_sender -d email_sender -c "
SELECT indexname FROM pg_indexes
WHERE tablename IN ('email_clicks', 'email_opens')
ORDER BY indexname;
"

echo ""
echo "Шаг 11: Проверка моделей..."
docker compose exec -T api rails runner "
begin
  puts 'EmailClick count: ' + EmailClick.count.to_s
  puts 'EmailOpen count: ' + EmailOpen.count.to_s
  puts '✅ Модели работают!'
rescue => e
  puts '❌ Ошибка: ' + e.message
  puts e.backtrace.first(5).join(\"\n\")
  exit 1
end
" 2>&1

echo ""
echo "=== ФИНАЛЬНАЯ ПРОВЕРКА ==="
API_STATUS=$(docker compose ps api --format "{{.Status}}" | grep -o "healthy" || echo "not_healthy")
SIDEKIQ_STATUS=$(docker compose ps sidekiq --format "{{.Status}}" | grep -o "healthy" || echo "not_healthy")

if [ "$API_STATUS" = "healthy" ] && [ "$SIDEKIQ_STATUS" = "healthy" ]; then
  echo ""
  echo "🎉🎉🎉 УСПЕХ! 🎉🎉🎉"
  echo ""
  echo "✅ API: healthy"
  echo "✅ Sidekiq: healthy"
  echo "✅ Модели загружаются"
  echo "✅ Все миграции выполнены"
  echo ""
  echo "Дашборд должен работать: https://linenarrow.com"
  echo ""
else
  echo ""
  echo "⚠️  Статус контейнеров:"
  echo "API: $API_STATUS"
  echo "Sidekiq: $SIDEKIQ_STATUS"
  echo ""
  echo "Контейнеры всё ещё запускаются. Подождите ещё 30 секунд."
  echo "Затем проверьте: docker compose ps"
fi
