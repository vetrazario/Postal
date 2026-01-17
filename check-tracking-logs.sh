#!/bin/bash

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  ПРОВЕРКА ЛОГОВ ТРЕКИНГА                                   ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

cd /opt/email-sender

echo "1. ЛОГИ API (последние 50 строк с фильтром tracking/click/open):"
echo "─────────────────────────────────────────────────────────────"
docker compose logs api --tail=50 | grep -iE '(tracking|click|open|/go/)' || echo "   Нет логов о трекинге"

echo ""
echo "2. ЛОГИ SIDEKIQ (последние 50 строк с фильтром error/failed/delivery):"
echo "─────────────────────────────────────────────────────────────"
docker compose logs sidekiq --tail=50 | grep -iE '(error|failed|delivery|smtp)' || echo "   Нет логов об ошибках"

echo ""
echo "3. ПОСЛЕДНИЕ ЗАПРОСЫ К /go/ (если есть):"
echo "─────────────────────────────────────────────────────────────"
docker compose logs api --tail=200 | grep 'GET "/go/' | tail -5 || echo "   Нет запросов к /go/"

echo ""
echo "4. ПОСЛЕДНИЕ ЗАПРОСЫ К /t/o/ (tracking pixel):"
echo "─────────────────────────────────────────────────────────────"
docker compose logs api --tail=200 | grep 'GET "/t/o/' | tail -5 || echo "   Нет запросов к /t/o/"

echo ""
echo "✅ Проверка логов завершена"
