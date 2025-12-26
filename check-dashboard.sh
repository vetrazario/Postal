#!/bin/bash
# Скрипт для диагностики дашборда

echo "🔍 Диагностика дашборда..."
echo ""

# 1. Проверить, какой контроллер используется
echo "📋 Проверка маршрутов:"
docker compose exec api bundle exec rails routes | grep dashboard | head -10

echo ""
echo "📋 Проверка BaseController:"
docker compose exec api cat app/controllers/dashboard/base_controller.rb | grep -A 5 "class BaseController"

echo ""
echo "📋 Проверка layout:"
docker compose exec api ls -la app/views/layouts/ | grep dashboard

echo ""
echo "📋 Проверка логов (последние ошибки):"
docker compose logs api | grep -i error | tail -10

echo ""
echo "✅ Диагностика завершена"

