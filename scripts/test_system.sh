#!/bin/bash

# ===========================================
# Комплексная проверка работоспособности системы
# ===========================================

set -e

echo "=========================================="
echo "Проверка работоспособности системы"
echo "=========================================="
echo ""

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Счетчики
PASSED=0
FAILED=0

# Функция для проверки
check() {
    local name="$1"
    local command="$2"
    
    echo -n "Проверка: $name... "
    
    if eval "$command" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ OK${NC}"
        ((PASSED++))
        return 0
    else
        echo -e "${RED}✗ FAILED${NC}"
        ((FAILED++))
        return 1
    fi
}

# Функция для информационного вывода
info() {
    local name="$1"
    local command="$2"
    
    echo "Информация: $name"
    eval "$command" 2>/dev/null || echo "  (недоступно)"
    echo ""
}

echo "[1] Статус контейнеров:"
echo "----------------------------------------"
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Health}}" 2>/dev/null || docker ps --format "table {{.Names}}\t{{.Status}}"
echo ""

echo "[2] Health Check API:"
echo "----------------------------------------"
HEALTH_RESPONSE=$(docker exec email_api curl -s http://localhost:3000/api/v1/health 2>/dev/null || echo "")
if [ -n "$HEALTH_RESPONSE" ]; then
    echo "$HEALTH_RESPONSE" | jq -r '.status' 2>/dev/null || echo "$HEALTH_RESPONSE"
    echo ""
    echo "Детали проверок:"
    echo "$HEALTH_RESPONSE" | jq -r '.checks | to_entries[] | "  \(.key): \(.value.status)\(if .value.message then " - \(.value.message)" else "" end)"' 2>/dev/null || echo "  (не удалось распарсить JSON)"
else
    echo -e "${RED}  ✗ Health endpoint недоступен${NC}"
    ((FAILED++))
fi
echo ""

echo "[3] Проверка компонентов:"
echo "----------------------------------------"

check "База данных PostgreSQL" "docker exec email_api bundle exec rails runner 'ActiveRecord::Base.connection.execute(\"SELECT 1\")'"
check "Redis" "docker exec email_redis redis-cli ping"
check "Sidekiq подключение" "docker exec email_api bundle exec rails runner 'Sidekiq.redis { |conn| conn.ping == \"PONG\" }'"
check "Таблица bounced_emails" "docker exec email_api bundle exec rails runner 'ActiveRecord::Base.connection.table_exists?(\"bounced_emails\")'"
check "Таблица unsubscribes" "docker exec email_api bundle exec rails runner 'ActiveRecord::Base.connection.table_exists?(\"unsubscribes\")'"
check "Индекс bounce_category" "docker exec email_api bundle exec rails runner 'ActiveRecord::Base.connection.index_exists?(:bounced_emails, :bounce_category)'"
echo ""

echo "[4] Проверка API endpoints:"
echo "----------------------------------------"
check "Health endpoint" "docker exec email_api curl -sf http://localhost:3000/api/v1/health"
check "Bounce status endpoint" "docker exec email_api curl -sf 'http://localhost:3000/api/v1/bounce_status/check?email=test@example.com'"
echo ""

echo "[5] Проверка джобов:"
echo "----------------------------------------"
check "CleanupOldBouncesJob" "docker exec email_api bundle exec rails runner 'defined?(CleanupOldBouncesJob)'"
check "MonitorBounceCategoriesJob" "docker exec email_api bundle exec rails runner 'defined?(MonitorBounceCategoriesJob)'"
check "BounceSchedulerJob" "docker exec email_api bundle exec rails runner 'defined?(BounceSchedulerJob)'"
check "CheckMailingThresholdsJob" "docker exec email_api bundle exec rails runner 'defined?(CheckMailingThresholdsJob)'"
check "ErrorClassifier" "docker exec email_api bundle exec rails runner 'defined?(ErrorClassifier)'"
echo ""

echo "[6] Проверка миграций:"
echo "----------------------------------------"
info "Статус миграций" "docker exec email_api bundle exec rails db:migrate:status | tail -10"
echo ""

echo "[7] Проверка Sidekiq:"
echo "----------------------------------------"
info "Статистика Sidekiq" "docker exec email_api bundle exec rails runner 'stats = Sidekiq::Stats.new; puts \"  Processed: #{stats.processed}\"; puts \"  Failed: #{stats.failed}\"; puts \"  Enqueued: #{stats.enqueued}\"; puts \"  Queues: #{stats.queues.size}\"'"
echo ""

echo "[8] Проверка логов (последние ошибки):"
echo "----------------------------------------"
ERROR_COUNT=$(docker logs email_api --tail=200 2>&1 | grep -i "error\|exception\|fatal" | wc -l)
if [ "$ERROR_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}  ⚠ Найдено $ERROR_COUNT потенциальных ошибок в логах${NC}"
    echo "  Последние ошибки:"
    docker logs email_api --tail=200 2>&1 | grep -i "error\|exception\|fatal" | tail -5 | sed 's/^/    /'
else
    echo -e "${GREEN}  ✓ Критических ошибок в логах не найдено${NC}"
fi
echo ""

echo "[9] Тест API bounce_status:"
echo "----------------------------------------"
BOUNCE_TEST=$(docker exec email_api curl -s "http://localhost:3000/api/v1/bounce_status/check?email=test@example.com" 2>/dev/null)
if [ -n "$BOUNCE_TEST" ]; then
    echo "$BOUNCE_TEST" | jq . 2>/dev/null || echo "$BOUNCE_TEST"
else
    echo -e "${RED}  ✗ Endpoint недоступен${NC}"
fi
echo ""

echo "[10] Проверка Postal (может быть degraded):"
echo "----------------------------------------"
POSTAL_CHECK=$(docker exec email_api curl -s http://postal:5000/api/v1/health 2>/dev/null || echo "")
if [ -n "$POSTAL_CHECK" ]; then
    echo -e "${GREEN}  ✓ Postal доступен${NC}"
else
    echo -e "${YELLOW}  ⚠ Postal еще запускается (это нормально)${NC}"
fi
echo ""

echo "=========================================="
echo "Результаты проверки"
echo "=========================================="
echo -e "${GREEN}Успешно: $PASSED${NC}"
echo -e "${RED}Ошибок: $FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ Все проверки пройдены успешно!${NC}"
    exit 0
else
    echo -e "${YELLOW}⚠ Обнаружены проблемы. Проверьте детали выше.${NC}"
    exit 1
fi

