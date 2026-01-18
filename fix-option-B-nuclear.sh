#!/bin/bash
# Вариант Б: Полная Очистка (Ядерный вариант)
# ВНИМАНИЕ: Удаляет все данные отслеживания!

echo "=== ВНИМАНИЕ: ЯДЕРНЫЙ ВАРИАНТ ==="
echo ""
echo "Этот скрипт УДАЛИТ:"
echo "- Таблицу email_clicks (все данные о кликах)"
echo "- Таблицу email_opens (все данные об открытиях)"
echo "- Записи миграций из schema_migrations"
echo ""
echo "Затем создаст таблицы заново с нуля."
echo ""
echo "⚠️  ВСЕ ДАННЫЕ ОТСЛЕЖИВАНИЯ БУДУТ ПОТЕРЯНЫ! ⚠️"
echo ""
read -p "Вы УВЕРЕНЫ что хотите продолжить? (введите YES): " -r
if [[ ! $REPLY == "YES" ]]; then
  echo "Отменено (нужно ввести именно YES)"
  exit 1
fi

echo ""
echo "Шаг 1: Остановка контейнеров..."
docker compose stop api sidekiq

echo ""
echo "Шаг 2: Удаление таблиц..."
docker compose exec postgres psql -U email_sender -d email_sender -c "
DROP TABLE IF EXISTS email_clicks CASCADE;
DROP TABLE IF EXISTS email_opens CASCADE;
SELECT 'Таблицы удалены' as status;
"

echo ""
echo "Шаг 3: Удаление записей миграций..."
docker compose exec postgres psql -U email_sender -d email_sender -c "
DELETE FROM schema_migrations WHERE version IN (
  '20260114180000',
  '20260114180100',
  '20260114180200',
  '20260115000000',
  '20260116000000'
);
SELECT 'Миграции удалены' as status;
"

echo ""
echo "Шаг 4: Проверка что таблицы удалены..."
docker compose exec postgres psql -U email_sender -d email_sender -c "
SELECT table_name FROM information_schema.tables
WHERE table_name IN ('email_clicks', 'email_opens');
" | grep -E "email_clicks|email_opens" && echo "Ошибка: таблицы всё ещё существуют!" || echo "Подтверждено: таблицы удалены"

echo ""
echo "Шаг 5: Запуск контейнеров..."
docker compose start api sidekiq

echo ""
echo "Шаг 6: Ожидание запуска (30 секунд)..."
sleep 30

echo ""
echo "Шаг 7: Запуск миграций с нуля..."
docker compose exec api rails db:migrate RAILS_ENV=production 2>&1

echo ""
echo "Шаг 8: Перезапуск контейнеров..."
docker compose restart api sidekiq

echo ""
echo "Шаг 9: Ожидание (30 секунд)..."
sleep 30

echo ""
echo "Шаг 10: Проверка статуса контейнеров..."
docker compose ps

echo ""
echo "Шаг 11: Проверка миграций..."
docker compose exec postgres psql -U email_sender -d email_sender -c "
SELECT version FROM schema_migrations WHERE version LIKE '202601%' ORDER BY version;
"

echo ""
echo "Шаг 12: Проверка структуры таблиц..."
docker compose exec postgres psql -U email_sender -d email_sender -c "\d email_clicks"
echo ""
docker compose exec postgres psql -U email_sender -d email_sender -c "\d email_opens"

echo ""
echo "Шаг 13: Проверка что модели загружаются..."
docker compose exec api rails runner "
puts 'EmailClick count: ' + EmailClick.count.to_s
puts 'EmailOpen count: ' + EmailOpen.count.to_s
puts 'Система отслеживания работает!'
" 2>&1

echo ""
echo "=== Полная переустановка завершена ==="
echo "Все таблицы отслеживания были пересозданы с нуля."
