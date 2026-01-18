#!/bin/bash
set -e

echo "=== Быстрая проверка Error Monitor ==="
echo ""

cd /opt/email-sender

echo "1. Копируем скрипт в контейнер..."
docker compose cp check_error_monitor.rb api:/tmp/check_error_monitor.rb

echo ""
echo "2. Запускаем диагностику..."
docker compose exec api bundle exec rails runner /tmp/check_error_monitor.rb

echo ""
echo "=== Готово ==="
