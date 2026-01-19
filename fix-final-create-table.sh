#!/bin/bash
# Финальное исправление: создание таблицы email_opens вручную

set -e

echo "=== ФИНАЛЬНОЕ ИСПРАВЛЕНИЕ: Создание Таблицы email_opens ==="
echo ""

echo "Шаг 1: Остановка API контейнера..."
docker compose stop api

echo ""
echo "Шаг 2: Проверка существующих таблиц..."
docker compose exec postgres psql -U email_sender -d email_sender -c "
SELECT table_name FROM information_schema.tables
WHERE table_name IN ('email_clicks', 'email_opens')
ORDER BY table_name;
"

echo ""
echo "Шаг 3: Создание таблицы email_opens если не существует..."
docker compose exec -T postgres psql -U email_sender -d email_sender <<'EOF'
-- Создать таблицу email_opens если не существует
CREATE TABLE IF NOT EXISTS email_opens (
  id BIGSERIAL PRIMARY KEY,
  email_log_id BIGINT NOT NULL,
  campaign_id VARCHAR(255) NOT NULL,
  ip_address VARCHAR(45),
  user_agent VARCHAR(1024),
  token VARCHAR(255) NOT NULL,
  opened_at TIMESTAMP,
  created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Создать foreign key constraint если не существует
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'fk_rails_email_opens_email_log'
  ) THEN
    ALTER TABLE email_opens
    ADD CONSTRAINT fk_rails_email_opens_email_log
    FOREIGN KEY (email_log_id) REFERENCES email_logs(id);
  END IF;
END $$;

-- Создать индекс на token (unique) если не существует
CREATE UNIQUE INDEX IF NOT EXISTS index_email_opens_on_token ON email_opens(token);

-- Создать индекс на campaign_id и opened_at если не существует
CREATE INDEX IF NOT EXISTS index_email_opens_on_campaign_id_and_opened_at
ON email_opens(campaign_id, opened_at);

-- Создать индекс на email_log_id если не существует
CREATE INDEX IF NOT EXISTS index_email_opens_on_email_log_id ON email_opens(email_log_id);

-- Показать результат
\d email_opens

SELECT 'Таблица email_opens создана успешно!' as status;
EOF

echo ""
echo "Шаг 4: Проверка созданной таблицы..."
docker compose exec postgres psql -U email_sender -d email_sender -c "
SELECT
  column_name,
  data_type,
  character_maximum_length,
  is_nullable
FROM information_schema.columns
WHERE table_name = 'email_opens'
ORDER BY ordinal_position;
"

echo ""
echo "Шаг 5: Проверка индексов..."
docker compose exec postgres psql -U email_sender -d email_sender -c "
SELECT indexname FROM pg_indexes WHERE tablename = 'email_opens';
"

echo ""
echo "Шаг 6: Запуск API контейнера..."
docker compose start api

echo ""
echo "Шаг 7: Ожидание запуска (30 секунд)..."
sleep 30

echo ""
echo "Шаг 8: Проверка статуса контейнеров..."
docker compose ps

echo ""
echo "Шаг 9: Проверка логов API..."
docker compose logs api --tail=30

echo ""
echo "Шаг 10: Проверка что модели загружаются..."
docker compose exec api rails runner "
begin
  puts 'EmailClick count: ' + EmailClick.count.to_s
  puts 'EmailOpen count: ' + EmailOpen.count.to_s
  puts '✅ Таблицы работают!'
rescue => e
  puts '❌ Ошибка: ' + e.message
  exit 1
end
" 2>&1

echo ""
echo "Шаг 11: Проверка миграций..."
docker compose exec postgres psql -U email_sender -d email_sender -c "
SELECT version FROM schema_migrations WHERE version LIKE '202601%' ORDER BY version;
"

echo ""
echo "=== ГОТОВО ==="
echo ""
API_STATUS=$(docker compose ps api --format "{{.Status}}" | grep -o "healthy" || echo "not_healthy")
if [ "$API_STATUS" = "healthy" ]; then
  echo "🎉 API контейнер запущен успешно!"
  echo ""
  echo "Проверьте дашборд: https://linenarrow.com"
else
  echo "⚠️  API контейнер ещё запускается или есть ошибки."
  echo "Подождите ещё 30 секунд и проверьте: docker compose ps"
fi
