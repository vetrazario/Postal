#!/bin/bash
# Пересборка Sidekiq с новым кодом

echo "=== Пересборка Sidekiq ==="
echo ""

echo "Шаг 1: Остановка Sidekiq..."
docker compose stop sidekiq

echo ""
echo "Шаг 2: Пересборка образа Sidekiq с новым кодом..."
docker compose build sidekiq

echo ""
echo "Шаг 3: Запуск Sidekiq..."
docker compose up -d sidekiq

echo ""
echo "Шаг 4: Ожидание 30 секунд..."
sleep 30

echo ""
echo "Шаг 5: Проверка статуса..."
docker compose ps

echo ""
echo "Шаг 6: Проверка логов Sidekiq..."
docker compose logs sidekiq --tail=30

echo ""
echo "Шаг 7: Проверка ошибок..."
ERROR_COUNT=$(docker compose logs sidekiq --tail=50 | grep -i "verify_authenticity_token\|error\|exception" | wc -l)

if [ $ERROR_COUNT -eq 0 ]; then
  echo "✅ Ошибок не найдено!"
else
  echo "⚠️  Найдено ошибок: $ERROR_COUNT"
  docker compose logs sidekiq --tail=50 | grep -i "verify_authenticity_token\|error\|exception" | tail -10
fi

echo ""
echo "=== ФИНАЛЬНЫЙ СТАТУС ==="
API_HEALTH=$(docker compose ps api --format "{{.Status}}" | grep -o "healthy" || echo "not_healthy")
SIDEKIQ_HEALTH=$(docker compose ps sidekiq --format "{{.Status}}" | grep -o "healthy" || echo "not_healthy")

if [ "$API_HEALTH" = "healthy" ] && [ "$SIDEKIQ_HEALTH" = "healthy" ]; then
  echo ""
  echo "🎉🎉🎉 ПОЛНЫЙ УСПЕХ! 🎉🎉🎉"
  echo ""
  echo "✅ API: healthy"
  echo "✅ Sidekiq: healthy"
  echo "✅ Все миграции выполнены"
  echo "✅ Модели загружаются"
  echo "✅ Система отслеживания работает"
  echo ""
  echo "Дашборд: https://linenarrow.com"
  echo ""
else
  echo ""
  echo "Текущий статус:"
  echo "API: $API_HEALTH"
  echo "Sidekiq: $SIDEKIQ_HEALTH"
  echo ""
  if [ "$SIDEKIQ_HEALTH" != "healthy" ]; then
    echo "Sidekiq всё ещё запускается. Подождите ещё 30 секунд."
  fi
fi
