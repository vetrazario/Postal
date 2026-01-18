#!/bin/bash
# Simplified migration fix script
# Run this from /opt/email-sender

echo "=== Простое Исправление Миграций ==="
echo ""

# Step 1: Check container status
echo "Шаг 1: Проверка статуса контейнеров..."
docker compose ps
echo ""

# Step 2: Check API logs to see the actual error
echo "Шаг 2: Проверка логов API (последние 50 строк)..."
docker compose logs api --tail=50
echo ""

# Step 3: Try to connect to database and check tables
echo "Шаг 3: Проверка существующих таблиц в БД..."
docker compose exec postgres psql -U email_sender -d email_sender -c "\dt" 2>&1 | grep -E "email_clicks|email_opens|schema_migrations" || echo "Не удалось подключиться к БД или таблицы не найдены"
echo ""

# Step 4: If API container is restarting, check why
echo "Шаг 4: Проверка причины перезапуска API..."
API_STATUS=$(docker compose ps api --format json | grep -o '"State":"[^"]*"' || echo "unknown")
echo "Статус API: $API_STATUS"
echo ""

if [[ "$API_STATUS" == *"restarting"* ]] || [[ "$API_STATUS" == *"unhealthy"* ]]; then
  echo "API контейнер не запущен корректно. Показываю полные логи..."
  docker compose logs api --tail=200
  echo ""
  echo "=== РЕКОМЕНДАЦИЯ ==="
  echo "API контейнер не может запуститься. Возможные причины:"
  echo "1. Ошибка миграции (таблицы уже существуют)"
  echo "2. Ошибка подключения к БД"
  echo "3. Ошибка в коде приложения"
  echo ""
  echo "Попробуйте вариант А (безопасный) или вариант Б (полная очистка)"
  exit 1
fi

# Step 5: If API is running, try to run migrations
echo "Шаг 5: Попытка запустить миграции..."
docker compose exec api rails db:migrate RAILS_ENV=production 2>&1

# Step 6: Restart containers
echo ""
echo "Шаг 6: Перезапуск контейнеров..."
docker compose restart api sidekiq

# Step 7: Wait and check
echo ""
echo "Шаг 7: Ожидание запуска контейнеров (30 секунд)..."
sleep 30

echo ""
echo "Финальный статус:"
docker compose ps

echo ""
echo "=== Готово ==="
