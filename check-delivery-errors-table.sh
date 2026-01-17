#!/bin/bash

echo "Проверка структуры таблицы delivery_errors:"
echo ""

cd /opt/email-sender

docker compose exec -T postgres psql -U email_sender -d email_sender <<'SQL'
\d delivery_errors
SQL

echo ""
echo "Проверка какие миграции применены:"
docker compose exec -T postgres psql -U email_sender -d email_sender <<'SQL'
SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 10;
SQL
