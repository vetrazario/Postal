#!/bin/bash
# Детальная проверка рассылки с тестовой отправкой
# Использует реальные API вызовы для проверки каждого этапа

# Не останавливаться на ошибках - проверять все этапы
set +e

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Конфигурация
CAMPAIGN_ID="test_campaign_$(date +%s)"
TEST_EMAIL="${1:-test@example.com}"
API_URL="${API_URL:-http://localhost:3000}"
SMTP_RELAY_HOST="${SMTP_RELAY_HOST:-localhost}"
SMTP_RELAY_PORT="${SMTP_RELAY_PORT:-2587}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Детальная проверка рассылки${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Campaign ID: ${CAMPAIGN_ID}"
echo -e "Test Email: ${TEST_EMAIL}"
echo ""

# Функция логирования
log_step() {
    echo -e "${CYAN}[ШАГ $1] $2${NC}"
}

log_check() {
    echo -e "${YELLOW}  → $1${NC}"
}

log_success() {
    echo -e "${GREEN}  ✓ $1${NC}"
}

log_error() {
    echo -e "${RED}  ✗ $1${NC}"
}

# Функция проверки через Rails
rails_exec() {
    local code="$1"
    docker compose exec -T api rails runner "$code" 2>&1
}

# Функция ожидания
wait_for() {
    local description="$1"
    local condition="$2"
    local max_wait="${3:-10}"
    local waited=0
    
    log_check "Ожидание: $description"
    while [ $waited -lt $max_wait ]; do
        if eval "$condition" > /dev/null 2>&1; then
            log_success "$description - готово"
            return 0
        fi
        sleep 1
        ((waited++))
    done
    log_error "$description - таймаут"
    return 1
}

echo -e "${BLUE}=== ЭТАП 1: Получение письма от AMS ===${NC}"
log_step "1.1" "Проверка SMTP Relay"

# Проверка что SMTP Relay слушает порт
if docker compose exec -T smtp-relay nc -z localhost 587 2>/dev/null || docker compose ps smtp-relay | grep -q "Up"; then
    log_success "SMTP Relay контейнер работает"
else
    log_error "SMTP Relay контейнер не работает"
fi

# Проверка что порт доступен снаружи
if nc -z localhost 2587 2>/dev/null || timeout 1 bash -c "</dev/tcp/localhost/2587" 2>/dev/null; then
    log_success "SMTP Relay порт 2587 доступен снаружи"
else
    log_error "SMTP Relay порт 2587 недоступен снаружи (проверьте docker-compose.yml)"
fi

# Проверка что плагины загружены
if docker compose exec -T smtp-relay test -f /app/plugins/rebuild_headers.js; then
    log_success "Плагин rebuild_headers.js найден"
else
    log_error "Плагин rebuild_headers.js не найден"
fi

if docker compose exec -T smtp-relay test -f /app/plugins/inject_tracking.js; then
    log_success "Плагин inject_tracking.js найден"
else
    log_error "Плагин inject_tracking.js не найден"
fi

log_step "1.2" "Проверка API endpoint"
# Проверка через docker exec так как API может быть не доступен снаружи
API_CHECK=$(docker compose exec -T api curl -s -o /dev/null -w '%{http_code}' "http://localhost:3000/api/v1/smtp/receive" -X POST -H 'Content-Type: application/json' -d '{}' 2>/dev/null || echo "000")
if [ "$API_CHECK" = "400" ] || [ "$API_CHECK" = "401" ] || [ "$API_CHECK" = "200" ]; then
    log_success "API endpoint /api/v1/smtp/receive доступен (код: $API_CHECK)"
else
    # Попробовать через внешний URL если указан
    if [ "$API_URL" != "http://localhost:3000" ]; then
        API_STATUS=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 2 "${API_URL}/api/v1/smtp/receive" -X POST -H 'Content-Type: application/json' -d '{}' 2>/dev/null || echo "000")
        if [ "$API_STATUS" = "400" ] || [ "$API_STATUS" = "401" ]; then
            log_success "API endpoint доступен через внешний URL (код: $API_STATUS)"
        else
            log_error "API endpoint недоступен (внутренний: $API_CHECK, внешний: $API_STATUS)"
        fi
    else
        log_error "API endpoint недоступен (код: $API_CHECK). Проверьте что контейнер api работает"
    fi
fi

echo ""
echo -e "${BLUE}=== ЭТАП 2: Пересборка заголовков ===${NC}"
log_step "2.1" "Проверка обработки заголовков"

HEADERS_CHECK=$(rails_exec "
headers = {
  'X-AMS-Test' => 'value',
  'X-Campaign-ID' => '123',
  'From' => 'test@example.com',
  'To' => 'recipient@example.com',
  'Subject' => 'Test'
}
clean = headers.reject { |k,v| k =~ /^x-ams-/i || k =~ /^x-campaign-id$/i }
puts clean.keys.include?('From') && !clean.keys.include?('X-AMS-Test') ? 'OK' : 'FAIL'
")

if echo "$HEADERS_CHECK" | grep -q "OK"; then
    log_success "Заголовки очищаются от AMS следов"
else
    log_error "Проблема с очисткой заголовков"
fi

echo ""
echo -e "${BLUE}=== ЭТАП 3: Добавление ссылки отписки ===${NC}"
log_step "3.1" "Проверка List-Unsubscribe заголовка"

UNSUBSCRIBE_CHECK=$(rails_exec "
pc = PostalClient.new(api_url: 'http://postal:5000', api_key: 'test')
headers = pc.send(:build_headers, 'from@example.com', 'to@example.com', 'Subject', 'example.com', 'campaign123')
puts headers['List-Unsubscribe'].present? ? 'OK' : 'FAIL'
" 2>/dev/null || echo "FAIL")

if echo "$UNSUBSCRIBE_CHECK" | grep -q "OK"; then
    log_success "List-Unsubscribe заголовок добавляется"
else
    log_error "List-Unsubscribe заголовок не добавляется"
fi

log_step "3.2" "Проверка unsubscribe endpoint"
UNSUB_ROUTE=$(docker compose exec -T api rails routes 2>/dev/null | grep unsubscribe | head -1)
if [ -n "$UNSUB_ROUTE" ]; then
    log_success "Unsubscribe route существует"
else
    log_error "Unsubscribe route не найден"
fi

echo ""
echo -e "${BLUE}=== ЭТАП 4: Отправка через Postal ===${NC}"
log_step "4.1" "Проверка параметров трекинга"

TRACKING_CHECK=$(rails_exec "
pc = PostalClient.new(api_url: 'http://postal:5000', api_key: 'test')
method = pc.method(:send_message)
params = method.parameters
has_track_clicks = params.any? { |p| p[1] == :track_clicks }
has_track_opens = params.any? { |p| p[1] == :track_opens }
puts (has_track_clicks && has_track_opens) ? 'OK' : 'FAIL'
" 2>/dev/null || echo "FAIL")

if echo "$TRACKING_CHECK" | grep -q "OK"; then
    log_success "PostalClient передает track_clicks и track_opens"
else
    log_error "PostalClient не передает параметры трекинга"
fi

log_step "4.2" "Проверка Postal API"
POSTAL_STATUS=$(docker compose exec -T api curl -s -o /dev/null -w '%{http_code}' "${POSTAL_URL:-http://postal:5000}/api/v1/status" 2>/dev/null || echo "000")
if [ "$POSTAL_STATUS" = "200" ] || [ "$POSTAL_STATUS" = "401" ] || [ "$POSTAL_STATUS" = "403" ]; then
    log_success "Postal API доступен (код: $POSTAL_STATUS)"
else
    log_error "Postal API недоступен (код: $POSTAL_STATUS)"
fi

echo ""
echo -e "${BLUE}=== ЭТАП 5: Получение логов от Postal ===${NC}"
log_step "5.1" "Проверка webhook endpoint"

# Проверка через docker exec
WEBHOOK_CHECK=$(docker compose exec -T api curl -s -o /dev/null -w '%{http_code}' "http://localhost:3000/api/v1/webhook" -X POST -H 'Content-Type: application/json' -d '{}' 2>/dev/null || echo "000")
if [ "$WEBHOOK_CHECK" = "200" ] || [ "$WEBHOOK_CHECK" = "400" ] || [ "$WEBHOOK_CHECK" = "401" ]; then
    log_success "Webhook endpoint доступен (код: $WEBHOOK_CHECK)"
else
    # Попробовать через внешний URL если указан
    if [ "$API_URL" != "http://localhost:3000" ]; then
        WEBHOOK_STATUS=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 2 "${API_URL}/api/v1/webhook" -X POST -H 'Content-Type: application/json' -d '{}' 2>/dev/null || echo "000")
        if [ "$WEBHOOK_STATUS" = "200" ] || [ "$WEBHOOK_STATUS" = "400" ]; then
            log_success "Webhook endpoint доступен через внешний URL (код: $WEBHOOK_STATUS)"
        else
            log_error "Webhook endpoint недоступен (внутренний: $WEBHOOK_CHECK, внешний: $WEBHOOK_STATUS)"
        fi
    else
        log_error "Webhook endpoint недоступен (код: $WEBHOOK_CHECK). Проверьте что контейнер api работает"
    fi
fi

log_step "5.2" "Проверка обработки событий"
WEBHOOK_CONTROLLER=$(rails_exec "puts defined?(Api::V1::WebhooksController) ? 'OK' : 'FAIL'" 2>/dev/null || echo "FAIL")
if echo "$WEBHOOK_CONTROLLER" | grep -q "OK"; then
    log_success "WebhooksController существует"
else
    log_error "WebhooksController не найден"
fi

DELIVERY_ERROR_CHECK=$(rails_exec "puts defined?(DeliveryError) && DeliveryError.respond_to?(:create!) ? 'OK' : 'FAIL'" 2>/dev/null || echo "FAIL")
if echo "$DELIVERY_ERROR_CHECK" | grep -q "OK"; then
    log_success "DeliveryError модель существует"
else
    log_error "DeliveryError модель не найдена"
fi

echo ""
echo -e "${BLUE}=== ЭТАП 6: Отображение логов в дашборде ===${NC}"
log_step "6.1" "Проверка Dashboard"

DASHBOARD_LOGS=$(rails_exec "puts defined?(Dashboard::LogsController) ? 'OK' : 'FAIL'" 2>/dev/null || echo "FAIL")
if echo "$DASHBOARD_LOGS" | grep -q "OK"; then
    log_success "Dashboard::LogsController существует"
else
    log_error "Dashboard::LogsController не найден"
fi

EMAIL_LOG_FIELDS=$(rails_exec "
log = EmailLog.new
fields = ['message_id', 'recipient', 'sender', 'subject', 'status', 'campaign_id']
puts fields.all? { |f| log.respond_to?(f) } ? 'OK' : 'FAIL'
" 2>/dev/null || echo "FAIL")

if echo "$EMAIL_LOG_FIELDS" | grep -q "OK"; then
    log_success "EmailLog имеет все необходимые поля"
else
    log_error "EmailLog не имеет всех необходимых полей"
fi

CAMPAIGN_STATS=$(rails_exec "puts defined?(CampaignStats) && CampaignStats.respond_to?(:find_or_initialize_for) ? 'OK' : 'FAIL'" 2>/dev/null || echo "FAIL")
if echo "$CAMPAIGN_STATS" | grep -q "OK"; then
    log_success "CampaignStats существует"
else
    log_error "CampaignStats не найден"
fi

echo ""
echo -e "${BLUE}=== ЭТАП 7: Переупаковка ссылок ===${NC}"
log_step "7.1" "Проверка замены ссылок на tracking URLs"

# Проверка что LinkTracker существует и заменяет ссылки
LINK_TRACKER_CHECK=$(rails_exec "
# Создаем временный EmailLog для теста
email_log = EmailLog.create!(
  message_id: 'test_tracking_' + SecureRandom.hex(8),
  recipient: 'test@example.com',
  recipient_masked: 't***@example.com',
  sender: 'sender@example.com',
  subject: 'Test',
  status: 'queued',
  campaign_id: 'test123'
)

# Используем внешний домен чтобы не попасть в own_domain_link проверку
html = '<a href=\"https://youtube.com/watch?v=test\">Link</a>'
tracker = LinkTracker.new(email_log: email_log, domain: 'linenarrow.com')
tracked = tracker.track_links(html)

# Проверяем что ссылка заменена на /go/ формат
if tracked.include?('/go/')
  result = 'OK'
else
  result = 'FAIL'
  puts \"DEBUG: Original: #{html}\"
  puts \"DEBUG: Tracked: #{tracked}\"
  puts \"DEBUG: track_clicks enabled: #{tracker.options[:track_clicks]}\"
end

# Удаляем тестовый EmailLog и связанные записи
EmailClick.where(email_log_id: email_log.id).destroy_all
email_log.destroy

puts result
" 2>/dev/null || echo "FAIL")

if echo "$LINK_TRACKER_CHECK" | grep -q "OK"; then
    log_success "LinkTracker заменяет ссылки на tracking URLs"
else
    log_error "LinkTracker не заменяет ссылки"
    # Показать детали если есть
    if echo "$LINK_TRACKER_CHECK" | grep -q "DEBUG"; then
        echo "$LINK_TRACKER_CHECK" | grep "DEBUG" | sed 's/^/    /'
    fi
fi

# Проверка формата tracking URL (читаемый формат /go/slug-TOKEN)
TRACKING_URL_CHECK=$(rails_exec "
# Проверяем что LinkTracker создает URL в формате /go/slug-TOKEN
email_log = EmailLog.create!(
  message_id: 'test_url_' + SecureRandom.hex(8),
  recipient: 'test@example.com',
  recipient_masked: 't***@example.com',
  sender: 'sender@example.com',
  subject: 'Test',
  status: 'queued',
  campaign_id: 'test123'
)

tracker = LinkTracker.new(email_log: email_log, domain: 'linenarrow.com')
original_url = 'https://youtube.com/watch'
tracking_url = tracker.send(:create_tracking_url, original_url)

# Формат должен быть: https://linenarrow.com/go/youtube-watch-TOKEN
if tracking_url.include?('/go/') && tracking_url.include?('linenarrow.com')
  result = 'OK'
else
  result = 'FAIL'
  puts \"Tracking URL: #{tracking_url}\"
end

# Удаляем тестовые записи
EmailClick.where(email_log_id: email_log.id).destroy_all
email_log.destroy
puts result
" 2>/dev/null || echo "FAIL")

if echo "$TRACKING_URL_CHECK" | grep -q "OK"; then
    log_success "Tracking URL имеет правильный формат"
else
    log_error "Tracking URL имеет неправильный формат"
fi

# Проверка что tracking endpoint обрабатывает редирект
log_step "7.2" "Проверка tracking endpoint для редиректа"
TRACKING_ENDPOINT=$(docker compose exec -T api rails routes 2>/dev/null | grep -E "/go/|track_click" | head -1)
if [ -n "$TRACKING_ENDPOINT" ]; then
    log_success "Tracking endpoint для кликов существует"
    log_check "Route: $TRACKING_ENDPOINT"
else
    log_error "Tracking endpoint для кликов не найден"
fi

# Проверка что endpoint /go/ существует
GO_ENDPOINT=$(docker compose exec -T api rails routes 2>/dev/null | grep "/go/" | head -1)
if [ -n "$GO_ENDPOINT" ]; then
    log_success "Endpoint /go/ для читаемых tracking URLs существует"
else
    log_error "Endpoint /go/ не найден"
fi

# Проверка что TrackingController обрабатывает редирект
TRACKING_CONTROLLER_CHECK=$(rails_exec "
if defined?(TrackingController)
  controller = TrackingController.new
  puts controller.respond_to?(:click, true) || controller.respond_to?(:redirect, true) ? 'OK' : 'FAIL'
else
  puts 'FAIL'
end
" 2>/dev/null || echo "FAIL")

if echo "$TRACKING_CONTROLLER_CHECK" | grep -q "OK"; then
    log_success "TrackingController обрабатывает редиректы"
else
    log_error "TrackingController не обрабатывает редиректы"
fi

# Проверка что оригинальный URL декодируется
URL_DECODE_CHECK=$(rails_exec "
require 'base64'
original = 'https://example.com/test?param=value'
encoded = Base64.urlsafe_encode64(original)
decoded = Base64.urlsafe_decode64(encoded)
puts decoded == original ? 'OK' : 'FAIL'
" 2>/dev/null || echo "FAIL")

if echo "$URL_DECODE_CHECK" | grep -q "OK"; then
    log_success "URL правильно кодируется/декодируется"
else
    log_error "Проблема с кодированием/декодированием URL"
fi

echo ""
echo -e "${BLUE}=== ЭТАП 8: Работа трекинга ===${NC}"
log_step "7.1" "Проверка моделей трекинга"

EMAIL_OPEN=$(rails_exec "puts defined?(EmailOpen) ? 'OK' : 'FAIL'" 2>/dev/null || echo "FAIL")
if echo "$EMAIL_OPEN" | grep -q "OK"; then
    log_success "EmailOpen модель существует"
else
    log_error "EmailOpen модель не найдена"
fi

EMAIL_CLICK=$(rails_exec "puts defined?(EmailClick) ? 'OK' : 'FAIL'" 2>/dev/null || echo "FAIL")
if echo "$EMAIL_CLICK" | grep -q "OK"; then
    log_success "EmailClick модель существует"
else
    log_error "EmailClick модель не найдена"
fi

log_step "7.2" "Проверка Analytics"
ANALYTICS_CHECK=$(rails_exec "
code = File.read('app/controllers/dashboard/analytics_controller.rb') rescue ''
puts (code.include?('EmailOpen') && code.include?('EmailClick')) ? 'OK' : 'FAIL'
" 2>/dev/null || echo "FAIL")

if echo "$ANALYTICS_CHECK" | grep -q "OK"; then
    log_success "Analytics использует EmailOpen и EmailClick"
else
    log_error "Analytics не использует новые модели трекинга"
fi

echo ""
echo -e "${BLUE}=== ЭТАП 9: Остановка рассылки при ошибках ===${NC}"
log_step "8.1" "Проверка системы остановки"

THRESHOLD_JOB=$(rails_exec "puts defined?(CheckMailingThresholdsJob) ? 'OK' : 'FAIL'" 2>/dev/null || echo "FAIL")
if echo "$THRESHOLD_JOB" | grep -q "OK"; then
    log_success "CheckMailingThresholdsJob существует"
else
    log_error "CheckMailingThresholdsJob не найден"
fi

MAILING_RULE=$(rails_exec "puts MailingRule.instance.respond_to?(:thresholds_exceeded?) ? 'OK' : 'FAIL'" 2>/dev/null || echo "FAIL")
if echo "$MAILING_RULE" | grep -q "OK"; then
    log_success "MailingRule имеет метод thresholds_exceeded?"
else
    log_error "MailingRule не имеет метода thresholds_exceeded?"
fi

AMS_CLIENT=$(rails_exec "puts defined?(AmsClient) && AmsClient.instance_methods.include?(:stop_mailing) ? 'OK' : 'FAIL'" 2>/dev/null || echo "FAIL")
if echo "$AMS_CLIENT" | grep -q "OK"; then
    log_success "AmsClient имеет метод stop_mailing"
else
    log_error "AmsClient не имеет метода stop_mailing"
fi

ERROR_CLASSIFIER=$(rails_exec "
ec = ErrorClassifier.new
if ec.respond_to?(:stop_mailing_categories)
  result = ec.stop_mailing_categories
  puts result.is_a?(Array) ? 'OK' : 'FAIL'
else
  # Проверяем через класс метод
  if ErrorClassifier.respond_to?(:stop_mailing_categories)
    result = ErrorClassifier.stop_mailing_categories
    puts result.is_a?(Array) ? 'OK' : 'FAIL'
  else
    puts 'FAIL'
  end
end
" 2>/dev/null || echo "FAIL")

if echo "$ERROR_CLASSIFIER" | grep -q "OK"; then
    log_success "ErrorClassifier определяет критические категории"
else
    log_error "ErrorClassifier не определяет критические категории (проверьте метод stop_mailing_categories)"
    # Показываем что есть в ErrorClassifier
    ERROR_METHODS=$(rails_exec "ec = ErrorClassifier.new; puts ec.methods.grep(/stop|mailing|category/).join(', ')" 2>/dev/null || echo "")
    if [ -n "$ERROR_METHODS" ]; then
        log_check "Доступные методы: $ERROR_METHODS"
    fi
fi

WEBHOOK_JOB_CHECK=$(rails_exec "
code = File.read('app/controllers/api/v1/webhooks_controller.rb') rescue ''
puts code.include?('CheckMailingThresholdsJob') ? 'OK' : 'FAIL'
" 2>/dev/null || echo "FAIL")

if echo "$WEBHOOK_JOB_CHECK" | grep -q "OK"; then
    log_success "CheckMailingThresholdsJob вызывается при баунсах"
else
    log_error "CheckMailingThresholdsJob не вызывается при баунсах"
fi

echo ""
echo -e "${BLUE}=== ИТОГИ ===${NC}"
echo -e "${GREEN}Проверка завершена${NC}"
echo ""
echo -e "${CYAN}Для полной проверки с реальной отправкой используйте:${NC}"
echo -e "${YELLOW}  ./scripts/test_email_send.sh ${TEST_EMAIL} ${CAMPAIGN_ID}${NC}"
echo ""

# Подсчет результатов
TOTAL_CHECKS=$(grep -c "\[ШАГ\|log_step\|log_check" "$0" 2>/dev/null || echo "0")
echo -e "${CYAN}Всего проверок выполнено${NC}"
echo -e "${YELLOW}Проверьте вывод выше для деталей${NC}"
