#!/bin/bash
# Диагностика и исправление проблемы Sidekiq

echo "=== Диагностика Sidekiq ==="
echo ""

echo "Шаг 1: Проверка логов Sidekiq (последние 100 строк)..."
docker compose logs sidekiq --tail=100

echo ""
echo "Шаг 2: Проверка healthcheck..."
docker compose exec sidekiq ps aux 2>&1 | head -20 || echo "Контейнер недоступен"

echo ""
echo "Шаг 3: Попытка запуска Sidekiq вручную для диагностики..."
docker compose exec sidekiq bundle exec sidekiq --version 2>&1 || echo "Ошибка при запуске Sidekiq"

echo ""
echo "=== Рекомендации ==="
echo ""
echo "Если видите ошибку про контроллеры - нужно пересобрать Sidekiq образ:"
echo "  docker compose build sidekiq"
echo "  docker compose restart sidekiq"
