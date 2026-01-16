#!/bin/bash
# Быстрое создание таблицы email_opens (API уже остановлен)

echo "=== Создание Таблицы email_opens ==="
echo ""

echo "API контейнер уже остановлен, продолжаем..."
echo ""

echo "Шаг 1: Создание таблицы..."
docker compose exec -T postgres psql -U email_sender -d email_sender <<'EOF'
-- Создать таблицу email_opens
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

-- Создать индексы
CREATE UNIQUE INDEX IF NOT EXISTS index_email_opens_on_token ON email_opens(token);
CREATE INDEX IF NOT EXISTS index_email_opens_on_campaign_id_and_opened_at ON email_opens(campaign_id, opened_at);
CREATE INDEX IF NOT EXISTS index_email_opens_on_email_log_id ON email_opens(email_log_id);

SELECT 'Таблица email_opens создана!' as status;
EOF

echo ""
echo "Шаг 2: Проверка таблицы..."
docker compose exec -T postgres psql -U email_sender -d email_sender -c "\d email_opens"

echo ""
echo "Шаг 3: Проверка обеих таблиц..."
docker compose exec -T postgres psql -U email_sender -d email_sender -c "
SELECT table_name FROM information_schema.tables
WHERE table_name IN ('email_clicks', 'email_opens')
ORDER BY table_name;
"

echo ""
echo "Шаг 4: Запуск API контейнера..."
docker compose start api

echo ""
echo "Шаг 5: Ожидание 30 секунд..."
sleep 30

echo ""
echo "Шаг 6: Проверка статуса..."
docker compose ps

echo ""
echo "Шаг 7: Проверка логов (последние 30 строк)..."
docker compose logs api --tail=30

echo ""
echo "Шаг 8: Проверка моделей..."
docker compose exec -T api rails runner "
puts 'EmailClick: ' + EmailClick.count.to_s
puts 'EmailOpen: ' + EmailOpen.count.to_s
puts '✅ Работает!'
"

echo ""
echo "=== ГОТОВО ==="
