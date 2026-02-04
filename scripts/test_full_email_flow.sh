#!/bin/bash
# ===========================================
# ПОЛНЫЙ ТЕСТ EMAIL FLOW
# ===========================================
# Отправляет тестовое письмо через API и отслеживает:
# 1. Создание EmailLog
# 2. Отправку в Postal
# 3. Получение webhook от Postal
# 4. Обновление статуса
# ===========================================

set -e

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Параметры
DOMAIN="${DOMAIN:-linenarrow.com}"
API_URL="${API_URL:-https://${DOMAIN}}"
TEST_RECIPIENT="${1:-test@example.com}"
MESSAGE_ID="test_$(date +%s)_$$"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   ПОЛНЫЙ ТЕСТ EMAIL FLOW${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${CYAN}Domain:${NC} ${DOMAIN}"
echo -e "${CYAN}API URL:${NC} ${API_URL}"
echo -e "${CYAN}Test Recipient:${NC} ${TEST_RECIPIENT}"
echo -e "${CYAN}Message ID:${NC} ${MESSAGE_ID}"
echo ""

# Получить API_KEY из .env (безопасно, без source)
if [ -f .env ]; then
    API_KEY=$(grep "^API_KEY=" .env | cut -d'=' -f2 | tr -d '\r\n"')
    POSTAL_API_KEY=$(grep "^POSTAL_API_KEY=" .env | cut -d'=' -f2 | tr -d '\r\n"')
fi

if [ -z "$API_KEY" ]; then
    echo -e "${RED}ERROR: API_KEY не найден в .env${NC}"
    echo "Установите API_KEY в файле .env или как переменную окружения"
    exit 1
fi

echo -e "${GREEN}✓ API_KEY найден${NC}"
echo ""

# ===========================================
# ШАГ 1: Отправка письма через API
# ===========================================
echo -e "${YELLOW}[ШАГ 1] Отправка письма через API...${NC}"

SEND_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${API_URL}/api/v1/send" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{
        \"recipient\": \"${TEST_RECIPIENT}\",
        \"template_id\": \"test_template\",
        \"from_name\": \"Test Sender\",
        \"from_email\": \"noreply@${DOMAIN}\",
        \"subject\": \"Test Email - ${MESSAGE_ID}\",
        \"variables\": {
            \"name\": \"Test User\",
            \"test_id\": \"${MESSAGE_ID}\"
        },
        \"tracking\": {
            \"campaign_id\": \"test_campaign_${MESSAGE_ID}\",
            \"message_id\": \"${MESSAGE_ID}\"
        },
        \"options\": {
            \"priority\": \"high\"
        }
    }")

HTTP_CODE=$(echo "$SEND_RESPONSE" | tail -1)
RESPONSE_BODY=$(echo "$SEND_RESPONSE" | sed '$d')

echo -e "${CYAN}HTTP Code:${NC} ${HTTP_CODE}"
echo -e "${CYAN}Response:${NC}"
echo "$RESPONSE_BODY" | jq . 2>/dev/null || echo "$RESPONSE_BODY"
echo ""

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "202" ]; then
    echo -e "${GREEN}✓ Письмо успешно отправлено в очередь${NC}"
    LOCAL_MESSAGE_ID=$(echo "$RESPONSE_BODY" | jq -r '.message_id // .data.message_id // empty' 2>/dev/null)
    if [ -n "$LOCAL_MESSAGE_ID" ]; then
        echo -e "${CYAN}Local Message ID:${NC} ${LOCAL_MESSAGE_ID}"
    fi
else
    echo -e "${RED}✗ Ошибка отправки письма (HTTP ${HTTP_CODE})${NC}"
    exit 1
fi
echo ""

# ===========================================
# ШАГ 2: Проверка EmailLog в базе
# ===========================================
echo -e "${YELLOW}[ШАГ 2] Проверка EmailLog в базе данных...${NC}"

sleep 2  # Дать время на обработку

EMAIL_LOG_CHECK=$(docker compose exec -T api rails runner "
log = EmailLog.find_by(external_message_id: '${MESSAGE_ID}')
if log
  puts 'FOUND'
  puts \"ID: #{log.id}\"
  puts \"Status: #{log.status}\"
  puts \"Recipient: #{log.recipient_masked}\"
  puts \"Subject: #{log.subject}\"
  puts \"Created: #{log.created_at}\"
  puts \"Postal ID: #{log.postal_message_id || 'pending'}\"
else
  puts 'NOT_FOUND'
end
" 2>/dev/null)

if echo "$EMAIL_LOG_CHECK" | grep -q "FOUND"; then
    echo -e "${GREEN}✓ EmailLog создан${NC}"
    echo "$EMAIL_LOG_CHECK" | grep -v "FOUND"
else
    echo -e "${RED}✗ EmailLog не найден${NC}"
    echo "Проверьте логи Sidekiq: docker compose logs sidekiq --tail=50"
fi
echo ""

# ===========================================
# ШАГ 3: Проверка очереди Sidekiq
# ===========================================
echo -e "${YELLOW}[ШАГ 3] Проверка очереди Sidekiq...${NC}"

SIDEKIQ_STATUS=$(docker compose exec -T api rails runner "
require 'sidekiq/api'
stats = Sidekiq::Stats.new
puts \"Processed: #{stats.processed}\"
puts \"Failed: #{stats.failed}\"
puts \"Enqueued: #{stats.enqueued}\"
puts \"Retries: #{stats.retry_size}\"

# Проверить активные воркеры
workers = Sidekiq::Workers.new
puts \"Active workers: #{workers.size}\"

# Проверить очереди
Sidekiq::Queue.all.each do |queue|
  puts \"Queue '#{queue.name}': #{queue.size} jobs\"
end
" 2>/dev/null)

echo "$SIDEKIQ_STATUS"
echo ""

# ===========================================
# ШАГ 4: Ожидание отправки в Postal
# ===========================================
echo -e "${YELLOW}[ШАГ 4] Ожидание отправки в Postal (до 30 сек)...${NC}"

for i in {1..15}; do
    POSTAL_ID=$(docker compose exec -T api rails runner "
log = EmailLog.find_by(external_message_id: '${MESSAGE_ID}')
if log && log.postal_message_id.present?
  puts log.postal_message_id
end
" 2>/dev/null | tr -d '\r\n')
    
    if [ -n "$POSTAL_ID" ]; then
        echo -e "${GREEN}✓ Письмо отправлено в Postal${NC}"
        echo -e "${CYAN}Postal Message ID:${NC} ${POSTAL_ID}"
        break
    fi
    
    echo -n "."
    sleep 2
done

if [ -z "$POSTAL_ID" ]; then
    echo ""
    echo -e "${RED}✗ Письмо не отправлено в Postal за 30 секунд${NC}"
    echo "Проверьте логи:"
    echo "  docker compose logs sidekiq --tail=50"
    echo "  docker compose logs api --tail=50"
fi
echo ""

# ===========================================
# ШАГ 5: Проверка статуса в Postal
# ===========================================
if [ -n "$POSTAL_ID" ]; then
    echo -e "${YELLOW}[ШАГ 5] Проверка статуса в Postal...${NC}"
    
    # Проверяем через Postal API (если есть POSTAL_API_KEY)
    if [ -n "$POSTAL_API_KEY" ]; then
        POSTAL_STATUS=$(curl -s "${API_URL}/postal/api/v1/messages/${POSTAL_ID}" \
            -H "X-Server-API-Key: ${POSTAL_API_KEY}" 2>/dev/null)
        echo "$POSTAL_STATUS" | jq . 2>/dev/null || echo "$POSTAL_STATUS"
    else
        echo -e "${CYAN}POSTAL_API_KEY не задан, пропускаем прямую проверку Postal${NC}"
    fi
fi
echo ""

# ===========================================
# ШАГ 6: Проверка финального статуса EmailLog
# ===========================================
echo -e "${YELLOW}[ШАГ 6] Финальный статус EmailLog...${NC}"

FINAL_STATUS=$(docker compose exec -T api rails runner "
log = EmailLog.find_by(external_message_id: '${MESSAGE_ID}')
if log
  puts \"Status: #{log.status}\"
  puts \"Postal ID: #{log.postal_message_id}\"
  puts \"Sent at: #{log.sent_at}\"
  puts \"Delivered at: #{log.delivered_at}\"
  puts \"Opened at: #{log.opened_at}\"
  puts \"Clicked at: #{log.clicked_at}\"
  puts \"Error: #{log.error_message}\" if log.error_message.present?
end
" 2>/dev/null)

echo "$FINAL_STATUS"
echo ""

# ===========================================
# ШАГ 7: Проверка TrackingEvents
# ===========================================
echo -e "${YELLOW}[ШАГ 7] Проверка TrackingEvents...${NC}"

TRACKING_EVENTS=$(docker compose exec -T api rails runner "
log = EmailLog.find_by(external_message_id: '${MESSAGE_ID}')
if log
  events = TrackingEvent.where(email_log_id: log.id).order(:created_at)
  if events.any?
    events.each do |e|
      puts \"#{e.created_at}: #{e.event_type} - #{e.details}\"
    end
  else
    puts 'No tracking events yet'
  end
end
" 2>/dev/null)

echo "$TRACKING_EVENTS"
echo ""

# ===========================================
# ИТОГИ
# ===========================================
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   ИТОГИ ТЕСТА${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${CYAN}Message ID:${NC} ${MESSAGE_ID}"
echo -e "${CYAN}Recipient:${NC} ${TEST_RECIPIENT}"

# Финальная проверка
FINAL_CHECK=$(docker compose exec -T api rails runner "
log = EmailLog.find_by(external_message_id: '${MESSAGE_ID}')
if log
  case log.status
  when 'delivered'
    puts 'DELIVERED'
  when 'sent'
    puts 'SENT'
  when 'queued', 'pending'
    puts 'QUEUED'
  when 'failed', 'bounced'
    puts 'FAILED'
  else
    puts log.status.upcase
  end
else
  puts 'NOT_FOUND'
end
" 2>/dev/null | tr -d '\r\n')

case "$FINAL_CHECK" in
    "DELIVERED")
        echo -e "${GREEN}✓ Письмо успешно доставлено!${NC}"
        ;;
    "SENT")
        echo -e "${GREEN}✓ Письмо отправлено, ожидает подтверждения доставки${NC}"
        ;;
    "QUEUED")
        echo -e "${YELLOW}⏳ Письмо в очереди на отправку${NC}"
        ;;
    "FAILED")
        echo -e "${RED}✗ Ошибка отправки письма${NC}"
        ;;
    *)
        echo -e "${YELLOW}? Статус: ${FINAL_CHECK}${NC}"
        ;;
esac

echo ""
echo -e "${CYAN}Для мониторинга webhook'ов:${NC}"
echo "  docker compose logs api --tail=50 -f | grep -i webhook"
echo ""
echo -e "${CYAN}Для проверки Sidekiq:${NC}"
echo "  docker compose logs sidekiq --tail=50"
echo ""
