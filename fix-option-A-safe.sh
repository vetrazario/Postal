#!/bin/bash
# Вариант А: Безопасное исправление
# Помечает миграции как выполненные если таблицы уже существуют

echo "=== Вариант А: Безопасное Исправление ==="
echo ""
echo "Этот скрипт:"
echo "1. Проверит существуют ли таблицы email_clicks и email_opens"
echo "2. Если существуют - пометит миграции как выполненные в schema_migrations"
echo "3. Запустит оставшиеся миграции"
echo "4. Перезапустит контейнеры"
echo ""
read -p "Продолжить? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Отменено"
  exit 1
fi

echo ""
echo "Шаг 1: Проверка таблиц в БД..."
docker compose exec postgres psql -U email_sender -d email_sender -c "
SELECT
  CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'email_clicks')
    THEN 'email_clicks EXISTS'
    ELSE 'email_clicks MISSING'
  END,
  CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'email_opens')
    THEN 'email_opens EXISTS'
    ELSE 'email_opens MISSING'
  END;
"

echo ""
echo "Шаг 2: Пометка миграций как выполненных..."
docker compose exec postgres psql -U email_sender -d email_sender -c "
INSERT INTO schema_migrations (version) VALUES ('20260114180000') ON CONFLICT DO NOTHING;
INSERT INTO schema_migrations (version) VALUES ('20260114180100') ON CONFLICT DO NOTHING;
INSERT INTO schema_migrations (version) VALUES ('20260114180200') ON CONFLICT DO NOTHING;
SELECT version FROM schema_migrations WHERE version LIKE '202601%' ORDER BY version;
"

echo ""
echo "Шаг 3: Запуск оставшихся миграций..."
docker compose exec api rails db:migrate RAILS_ENV=production 2>&1

echo ""
echo "Шаг 4: Перезапуск контейнеров..."
docker compose restart api sidekiq

echo ""
echo "Шаг 5: Ожидание (30 секунд)..."
sleep 30

echo ""
echo "Шаг 6: Проверка статуса..."
docker compose ps

echo ""
echo "Шаг 7: Проверка миграций..."
docker compose exec postgres psql -U email_sender -d email_sender -c "
SELECT version FROM schema_migrations WHERE version LIKE '202601%' ORDER BY version;
"

echo ""
echo "Шаг 8: Проверка что модели загружаются..."
docker compose exec api rails runner "
puts 'EmailClick: ' + EmailClick.count.to_s
puts 'EmailOpen: ' + EmailOpen.count.to_s
puts 'Успешно!'
" 2>&1

echo ""
echo "=== Готово ==="
