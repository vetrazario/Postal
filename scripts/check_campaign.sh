#!/bin/bash
# ===========================================
# Проверка статуса кампании
# Использование: ./check_campaign.sh CAMPAIGN_ID
# ===========================================

set -e

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Проверка аргумента
CAMPAIGN_ID="$1"
if [ -z "$CAMPAIGN_ID" ]; then
    echo -e "${RED}Использование: $0 CAMPAIGN_ID${NC}"
    echo ""
    echo "Примеры:"
    echo "  $0 campaign_12345"
    echo "  $0 test_1234567890"
    exit 1
fi

cd /opt/email-sender

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Проверка кампании: ${YELLOW}$CAMPAIGN_ID${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

# --- 1. Общая статистика по статусам ---
echo -e "${CYAN}📊 Статусы писем:${NC}"
docker compose exec -T api rails runner "
  logs = EmailLog.where(campaign_id: '$CAMPAIGN_ID')
  total = logs.count
  if total == 0
    puts '  (нет писем с таким campaign_id)'
  else
    logs.group(:status).count.sort_by { |s, _| s }.each do |status, count|
      pct = (count * 100.0 / total).round(1)
      puts \"  #{status.ljust(12)} #{count.to_s.rjust(5)}  (#{pct}%)\"
    end
    puts \"  #{'─' * 28}\"
    puts \"  ВСЕГО        #{total.to_s.rjust(5)}\"
  end
"
echo ""

# --- 2. CampaignStats (агрегированная статистика) ---
echo -e "${CYAN}📈 Сводка (CampaignStats):${NC}"
docker compose exec -T api rails runner "
  s = CampaignStats.find_by(campaign_id: '$CAMPAIGN_ID')
  if s.nil?
    puts '  (статистика ещё не создана)'
  else
    puts \"  Отправлено:   #{s.total_sent}\"
    puts \"  Доставлено:   #{s.total_delivered}\"
    puts \"  Открыто:      #{s.total_opened}\"
    puts \"  Кликов:       #{s.total_clicked}\"
    puts \"  Отписок:      #{s.total_unsubscribed}\"
    puts \"  Bounced:      #{s.total_bounced}\"
    puts \"  Failed:       #{s.total_failed}\"
  end
"
echo ""

# --- 3. Последние письма ---
echo -e "${CYAN}📬 Последние 10 писем:${NC}"
docker compose exec -T api rails runner "
  logs = EmailLog.where(campaign_id: '$CAMPAIGN_ID').order(created_at: :desc).limit(10)
  if logs.empty?
    puts '  (нет писем)'
  else
    puts '  ID     | Получатель            | Статус     | Время'
    puts '  ─' * 30
    logs.each do |e|
      time = e.sent_at&.strftime('%H:%M:%S') || e.created_at.strftime('%H:%M:%S')
      puts \"  #{e.id.to_s.ljust(6)} | #{e.recipient_masked.to_s.ljust(21)} | #{e.status.ljust(10)} | #{time}\"
    end
  end
"
echo ""

# --- 4. События трекинга ---
echo -e "${CYAN}🔍 Последние события трекинга:${NC}"
docker compose exec -T api rails runner "
  events = TrackingEvent.joins(:email_log)
                        .where(email_logs: { campaign_id: '$CAMPAIGN_ID' })
                        .order(created_at: :desc)
                        .limit(15)
  if events.empty?
    puts '  (нет событий — письма ещё не открывали/не кликали)'
  else
    puts '  Время    | Тип         | Детали'
    puts '  ─' * 25
    events.each do |e|
      time = e.created_at.strftime('%H:%M:%S')
      detail = case e.event_type
               when 'click'
                 url = e.event_data&.dig('url') || e.event_data&.dig(:url) || ''
                 url.length > 40 ? url[0..37] + '...' : url
               when 'open'
                 'pixel'
               else
                 ''
               end
      puts \"  #{time} | #{e.event_type.ljust(11)} | #{detail}\"
    end
  end
"
echo ""

# --- 5. Ошибки доставки (если есть) ---
echo -e "${CYAN}⚠️  Ошибки доставки (последние 5):${NC}"
docker compose exec -T api rails runner "
  errors = DeliveryError.joins(:email_log)
                        .where(email_logs: { campaign_id: '$CAMPAIGN_ID' })
                        .order(created_at: :desc)
                        .limit(5)
  if errors.empty?
    puts '  (нет ошибок)'
  else
    errors.each do |err|
      puts \"  #{err.created_at.strftime('%H:%M:%S')} | #{err.category} | #{err.error_message.to_s[0..60]}\"
    end
  end
"
echo ""

# --- 6. Отписки ---
echo -e "${CYAN}🚫 Отписки по кампании:${NC}"
docker compose exec -T api rails runner "
  unsubs = Unsubscribe.where(campaign_id: '$CAMPAIGN_ID').order(created_at: :desc).limit(5)
  count = Unsubscribe.where(campaign_id: '$CAMPAIGN_ID').count
  if count == 0
    puts '  (нет отписок)'
  else
    puts \"  Всего отписок: #{count}\"
    unsubs.each do |u|
      email_masked = u.email.gsub(/(?<=.{2}).+(?=@)/, '***') rescue u.email
      puts \"  #{u.unsubscribed_at&.strftime('%H:%M:%S')} | #{email_masked}\"
    end
  end
"
echo ""

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Проверка завершена${NC}"
echo ""
