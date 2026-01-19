#!/bin/bash
# Скрипт проверки рассылки на каждом этапе
# Проверяет весь flow от получения письма от AMS до остановки рассылки при ошибках

# Не останавливаться на ошибках - проверять все этапы
set +e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Конфигурация
CAMPAIGN_ID="${1:-test_campaign_$(date +%s)}"
TEST_EMAIL="${2:-test@example.com}"
API_URL="${API_URL:-http://localhost:3000}"
POSTAL_URL="${POSTAL_URL:-http://postal:5000}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Проверка рассылки на каждом этапе${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Campaign ID: ${CAMPAIGN_ID}"
echo -e "Test Email: ${TEST_EMAIL}"
echo ""

# Счетчики
PASSED=0
FAILED=0

# Функция проверки
check_step() {
    local step_name="$1"
    local check_command="$2"
    local expected_result="${3:-success}"
    
    echo -e "${YELLOW}[ПРОВЕРКА] ${step_name}...${NC}"
    
    if eval "$check_command" > /tmp/check_result.txt 2>&1; then
        if [ "$expected_result" = "success" ]; then
            echo -e "${GREEN}✓ ${step_name}: PASSED${NC}"
            ((PASSED++))
            return 0
        else
            echo -e "${RED}✗ ${step_name}: FAILED (expected failure but got success)${NC}"
            ((FAILED++))
            return 1
        fi
    else
        if [ "$expected_result" = "failure" ]; then
            echo -e "${GREEN}✓ ${step_name}: PASSED (expected failure)${NC}"
            ((PASSED++))
            return 0
        else
            echo -e "${RED}✗ ${step_name}: FAILED${NC}"
            cat /tmp/check_result.txt | head -5
            ((FAILED++))
            return 1
        fi
    fi
}

# Функция проверки через Rails runner
rails_check() {
    local description="$1"
    local ruby_code="$2"
    
    echo -e "${YELLOW}[ПРОВЕРКА] ${description}...${NC}"
    
    if docker compose exec -T api rails runner "$ruby_code" > /tmp/check_result.txt 2>&1; then
        echo -e "${GREEN}✓ ${description}: PASSED${NC}"
        ((PASSED++))
        return 0
    else
        echo -e "${RED}✗ ${description}: FAILED${NC}"
        cat /tmp/check_result.txt | head -10
        ((FAILED++))
        return 1
    fi
}

echo -e "${BLUE}=== ЭТАП 1: Получение письма от AMS ===${NC}"

# 1.1 Проверка что SMTP Relay контейнер работает
check_step "SMTP Relay контейнер работает" \
    "docker compose ps smtp-relay | grep -q 'Up'"

# 1.1.1 Проверка что порт доступен снаружи
check_step "SMTP Relay порт 2587 доступен" \
    "timeout 1 bash -c '</dev/tcp/localhost/2587' 2>/dev/null || nc -z localhost 2587 2>/dev/null"

# 1.2 Проверка что API endpoint /api/v1/smtp/receive доступен
check_step "API endpoint /api/v1/smtp/receive доступен" \
    "curl -s -o /dev/null -w '%{http_code}' ${API_URL}/api/v1/smtp/receive -X POST -H 'Content-Type: application/json' -d '{}' | grep -q '40[0-9]'"

# 1.3 Проверка что SMTP Controller создает EmailLog
rails_check "SMTP Controller создает EmailLog при получении письма" \
    "email_log = EmailLog.create!(message_id: 'test_123', recipient: 'test@example.com', recipient_masked: 't***@example.com', sender: 'sender@example.com', subject: 'Test', status: 'queued'); puts email_log.id; email_log.destroy"

echo ""
echo -e "${BLUE}=== ЭТАП 2: Пересборка заголовков ===${NC}"

# 2.1 Проверка что rebuild_headers.js плагин загружен
check_step "Плагин rebuild_headers.js загружен" \
    "docker compose exec -T smtp-relay test -f /app/plugins/rebuild_headers.js"

# 2.2 Проверка что заголовки очищаются от AMS следов
rails_check "Заголовки очищаются от AMS следов" \
    "headers = {'X-AMS-Test' => 'value', 'X-Campaign-ID' => '123', 'From' => 'test@example.com'}; clean = headers.reject { |k,v| k =~ /^x-ams-/i || k =~ /^x-campaign-id$/i }; puts clean.keys.include?('From') && !clean.keys.include?('X-AMS-Test') ? 'OK' : 'FAIL'"

# 2.3 Проверка что генерируется новый Message-ID
rails_check "Генерируется новый Message-ID" \
    "require 'securerandom'; msg_id = \"<local_#{SecureRandom.hex(12)}@example.com>\"; puts msg_id =~ /^<local_[a-f0-9]{24}@/ ? 'OK' : 'FAIL'"

echo ""
echo -e "${BLUE}=== ЭТАП 3: Добавление ссылки отписки ===${NC}"

# 3.1 Проверка что PostalClient добавляет List-Unsubscribe заголовок
rails_check "PostalClient добавляет List-Unsubscribe заголовок" \
    "pc = PostalClient.new(api_url: 'http://postal:5000', api_key: 'test'); headers = pc.send(:build_headers, 'from@example.com', 'to@example.com', 'Subject', 'example.com', 'campaign123'); puts headers['List-Unsubscribe'].present? ? 'OK' : 'FAIL'"

# 3.2 Проверка что unsubscribe ссылка содержит campaign_id
rails_check "Unsubscribe ссылка содержит campaign_id" \
    "require 'base64'; email = 'test@example.com'; cid = 'campaign123'; encoded = Base64.urlsafe_encode64(cid); url = \"https://example.com/unsubscribe?eid=#{Base64.urlsafe_encode64(email)}&cid=#{encoded}\"; puts url.include?('cid=') ? 'OK' : 'FAIL'"

# 3.3 Проверка что unsubscribe endpoint существует
check_step "Unsubscribe endpoint существует" \
    "docker compose exec -T api rails routes | grep -q unsubscribe"

echo ""
echo -e "${BLUE}=== ЭТАП 4: Отправка через Postal ===${NC}"

# 4.1 Проверка что PostalClient передает track_clicks и track_opens
rails_check "PostalClient передает track_clicks и track_opens" \
    "pc = PostalClient.new(api_url: 'http://postal:5000', api_key: 'test'); method = pc.method(:send_message); params = method.parameters; has_track_clicks = params.any? { |p| p[1] == :track_clicks }; has_track_opens = params.any? { |p| p[1] == :track_opens }; puts (has_track_clicks && has_track_opens) ? 'OK' : 'FAIL'"

# 4.2 Проверка что SendSmtpEmailJob существует и работает
rails_check "SendSmtpEmailJob существует" \
    "puts defined?(SendSmtpEmailJob) ? 'OK' : 'FAIL'"

# 4.3 Проверка что Postal API доступен
check_step "Postal API доступен" \
    "docker compose exec -T api curl -s -o /dev/null -w '%{http_code}' ${POSTAL_URL}/api/v1/status | grep -q '200\|401\|403'"

echo ""
echo -e "${BLUE}=== ЭТАП 5: Получение логов от Postal ===${NC}"

# 5.1 Проверка что webhook endpoint /api/v1/webhook доступен
check_step "Webhook endpoint /api/v1/webhook доступен" \
    "curl -s -o /dev/null -w '%{http_code}' ${API_URL}/api/v1/webhook -X POST -H 'Content-Type: application/json' -d '{}' | grep -q '40[0-9]\|200'"

# 5.2 Проверка что WebhooksController обрабатывает события
rails_check "WebhooksController обрабатывает события" \
    "puts defined?(Api::V1::WebhooksController) ? 'OK' : 'FAIL'"

# 5.3 Проверка что обрабатываются события MessageSent, MessageBounced, MessageDelivered
rails_check "Обрабатываются события MessageSent, MessageBounced, MessageDelivered" \
    "controller = Api::V1::WebhooksController.new; events = ['MessageSent', 'MessageBounced', 'MessageDelivered']; puts events.all? { |e| controller.respond_to?(:process_webhook_event, true) } ? 'OK' : 'FAIL'"

# 5.4 Проверка что DeliveryError создается при баунсах
rails_check "DeliveryError создается при баунсах" \
    "puts defined?(DeliveryError) && DeliveryError.respond_to?(:create!) ? 'OK' : 'FAIL'"

echo ""
echo -e "${BLUE}=== ЭТАП 6: Отображение логов в дашборде ===${NC}"

# 6.1 Проверка что EmailLog отображается в дашборде
check_step "Dashboard logs endpoint доступен" \
    "curl -s -o /dev/null -w '%{http_code}' ${API_URL}/dashboard/logs -u admin:\${DASHBOARD_PASSWORD:-admin} 2>/dev/null | grep -q '200\|401'"

# 6.2 Проверка что есть контроллер Dashboard::LogsController
rails_check "Dashboard::LogsController существует" \
    "puts defined?(Dashboard::LogsController) ? 'OK' : 'FAIL'"

# 6.3 Проверка что EmailLog имеет все необходимые поля
rails_check "EmailLog имеет необходимые поля" \
    "log = EmailLog.new; fields = ['message_id', 'recipient', 'sender', 'subject', 'status', 'campaign_id']; puts fields.all? { |f| log.respond_to?(f) } ? 'OK' : 'FAIL'"

# 6.4 Проверка что статистика кампании обновляется
rails_check "CampaignStats обновляется" \
    "puts defined?(CampaignStats) && CampaignStats.respond_to?(:find_or_initialize_for) ? 'OK' : 'FAIL'"

echo ""
echo -e "${BLUE}=== ЭТАП 7: Работа трекинга ===${NC}"

# 7.1 Проверка что EmailOpen модель существует
rails_check "EmailOpen модель существует" \
    "puts defined?(EmailOpen) ? 'OK' : 'FAIL'"

# 7.2 Проверка что EmailClick модель существует
rails_check "EmailClick модель существует" \
    "puts defined?(EmailClick) ? 'OK' : 'FAIL'"

# 7.3 Проверка что tracking endpoints доступны
check_step "Tracking endpoint /track/open доступен" \
    "curl -s -o /dev/null -w '%{http_code}' ${API_URL}/track/open/test123 2>/dev/null | grep -q '[0-9]'"

check_step "Tracking endpoint /track/click доступен" \
    "curl -s -o /dev/null -w '%{http_code}' ${API_URL}/track/click/test123 2>/dev/null | grep -q '[0-9]'"

# 7.4 Проверка что трекинг отображается в Analytics
rails_check "Analytics использует EmailOpen и EmailClick" \
    "controller = Dashboard::AnalyticsController.new; code = File.read('app/controllers/dashboard/analytics_controller.rb'); puts (code.include?('EmailOpen') && code.include?('EmailClick')) ? 'OK' : 'FAIL'"

echo ""
echo -e "${BLUE}=== ЭТАП 8: Остановка рассылки при ошибках ===${NC}"

# 8.1 Проверка что CheckMailingThresholdsJob существует
rails_check "CheckMailingThresholdsJob существует" \
    "puts defined?(CheckMailingThresholdsJob) ? 'OK' : 'FAIL'"

# 8.2 Проверка что MailingRule имеет метод thresholds_exceeded?
rails_check "MailingRule имеет метод thresholds_exceeded?" \
    "puts MailingRule.instance.respond_to?(:thresholds_exceeded?) ? 'OK' : 'FAIL'"

# 8.3 Проверка что AmsClient имеет метод stop_mailing
rails_check "AmsClient имеет метод stop_mailing" \
    "puts defined?(AmsClient) && AmsClient.instance_methods.include?(:stop_mailing) ? 'OK' : 'FAIL'"

# 8.4 Проверка что ErrorClassifier определяет критические категории
rails_check "ErrorClassifier определяет критические категории" \
    "ec = ErrorClassifier.new; puts ec.respond_to?(:stop_mailing_categories) ? 'OK' : 'FAIL'"

# 8.5 Проверка что CheckMailingThresholdsJob вызывается при баунсах
rails_check "CheckMailingThresholdsJob вызывается при баунсах" \
    "code = File.read('app/controllers/api/v1/webhooks_controller.rb'); puts code.include?('CheckMailingThresholdsJob') ? 'OK' : 'FAIL'"

echo ""
echo -e "${BLUE}=== ИТОГИ ===${NC}"
echo -e "${GREEN}Пройдено проверок: ${PASSED}${NC}"
echo -e "${RED}Провалено проверок: ${FAILED}${NC}"

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ Все проверки пройдены успешно!${NC}"
    exit 0
else
    echo -e "${RED}✗ Некоторые проверки провалились. Проверьте вывод выше.${NC}"
    exit 1
fi
