#!/bin/bash
set -e

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  ДИАГНОСТИКА СИСТЕМЫ ТРЕКИНГА                              ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

cd /opt/email-sender

docker compose exec -T api bundle exec rails runner '
puts "=== ДИАГНОСТИКА СИСТЕМЫ ТРЕКИНГА ==="
puts ""

# 1. Проверка EmailClick
puts "1. EMAIL CLICKS"
puts "─────────────────────────────────────────────────────────────"
clicks_count = EmailClick.count
puts "   Всего записей EmailClick: #{clicks_count}"

if clicks_count > 0
  puts ""
  puts "   Последние 5 кликов:"
  EmailClick.order(created_at: :desc).limit(5).each do |click|
    token_preview = "#{click.token[0..15]}..."
    puts "   - ID: #{click.id}"
    puts "     Token: #{token_preview}"
    puts "     URL: #{click.url}"
    puts "     Clicked: #{click.clicked_at.present? ? "Yes (#{click.clicked_at})" : "No"}"
    puts "     Campaign: #{click.campaign_id}"
    puts ""
  end
  
  # Проверим как должна выглядеть tracking ссылка
  last_click = EmailClick.last
  domain = SystemConfig.get(:domain) || "localhost"
  tracking_domain = SystemConfig.get(:tracking_domain) || domain
  
  puts "   Пример tracking URL для последнего клика:"
  
  # Генерируем slug как в LinkTracker
  begin
    uri = URI.parse(last_click.url)
    domain_parts = uri.host.to_s.split(".")
    domain_name = domain_parts[-2] || "link"
    path_slug = uri.path.to_s.split("/").reject(&:blank?).first || "page"
    slug = "#{domain_name}-#{path_slug}".downcase.gsub(/[^a-z0-9-]/, "-").gsub(/-+/, "-")[0..29]
    
    tracking_url = "https://#{tracking_domain}/go/#{slug}-#{last_click.token[0..15]}"
    puts "   ✅ #{tracking_url}"
  rescue => e
    puts "   ❌ Error generating URL: #{e.message}"
  end
else
  puts "   ⚠️  Нет записей EmailClick - трекинг кликов не работает!"
  puts "   Проверь что LinkTracker вызывается в SendSmtpEmailJob"
end

puts ""
puts "2. EMAIL OPENS"
puts "─────────────────────────────────────────────────────────────"
opens_count = EmailOpen.count
puts "   Всего записей EmailOpen: #{opens_count}"

if opens_count > 0
  opened_count = EmailOpen.where.not(opened_at: nil).count
  puts "   Открыто: #{opened_count} из #{opens_count}"
  
  puts ""
  puts "   Последнее открытие:"
  last_open = EmailOpen.where.not(opened_at: nil).order(opened_at: :desc).first
  if last_open
    puts "   - ID: #{last_open.id}"
    puts "     Campaign: #{last_open.campaign_id}"
    puts "     Opened at: #{last_open.opened_at}"
    puts "     IP: #{last_open.ip_address}"
  end
end

puts ""
puts "3. DELIVERY ERRORS"
puts "─────────────────────────────────────────────────────────────"
errors_count = DeliveryError.count
puts "   Всего записей DeliveryError: #{errors_count}"

if errors_count > 0
  puts ""
  puts "   Последние 3 ошибки:"
  DeliveryError.order(created_at: :desc).limit(3).each do |error|
    puts "   - ID: #{error.id}"
    puts "     Campaign: #{error.campaign_id}"
    puts "     Category: #{error.category}"
    puts "     Message: #{error.smtp_message&.truncate(80)}"
    puts "     Domain: #{error.recipient_domain}"
    puts "     Created: #{error.created_at}"
    puts ""
  end
else
  puts "   ⚠️  Нет записей об ошибках"
  puts "   Либо все отправки успешны, либо ошибки не логируются"
end

puts ""
puts "4. SYSTEM CONFIG"
puts "─────────────────────────────────────────────────────────────"
config = SystemConfig.instance
puts "   Domain: #{config.domain rescue "N/A"}"
puts "   Tracking domain: #{SystemConfig.get(:tracking_domain) || "не настроен (используется domain)"}"
puts "   Enable click tracking: #{SystemConfig.get(:enable_click_tracking).inspect}"
puts "   Enable open tracking: #{SystemConfig.get(:enable_open_tracking).inspect}"
puts "   Max tracked links: #{SystemConfig.get(:max_tracked_links) || 10}"

puts ""
puts "5. EMAIL LOGS"
puts "─────────────────────────────────────────────────────────────"
total_logs = EmailLog.count
failed_logs = EmailLog.where(status: "failed").count
sent_logs = EmailLog.where(status: "sent").count

puts "   Всего EmailLog: #{total_logs}"
puts "   Отправлено: #{sent_logs}"
puts "   Ошибки: #{failed_logs}"

if failed_logs > 0
  puts ""
  puts "   Последние 3 ошибки из EmailLog:"
  EmailLog.where(status: "failed").order(created_at: :desc).limit(3).each do |log|
    puts "   - ID: #{log.id}"
    puts "     Campaign: #{log.campaign_id}"
    puts "     Recipient: #{log.recipient_masked}"
    puts "     Error: #{log.status_details.inspect}"
    puts ""
  end
end

puts ""
puts "╔════════════════════════════════════════════════════════════╗"
puts "║  РЕКОМЕНДАЦИИ                                              ║"
puts "╚════════════════════════════════════════════════════════════╝"
puts ""

if clicks_count == 0
  puts "❌ Нет EmailClick записей"
  puts "   → Проверь что LinkTracker.track_links вызывается"
  puts "   → Проверь что enable_click_tracking = true"
  puts ""
end

if opens_count == 0
  puts "❌ Нет EmailOpen записей"
  puts "   → Проверь что LinkTracker.add_tracking_pixel вызывается"
  puts "   → Проверь что enable_open_tracking = true"
  puts ""
end

if errors_count == 0 && failed_logs > 0
  puts "❌ Есть failed EmailLog, но нет DeliveryError"
  puts "   → Проверь что DeliveryError.create! вызывается в SendSmtpEmailJob"
  puts "   → Проверь логи Sidekiq: docker compose logs sidekiq --tail=50"
  puts ""
end

if clicks_count > 0 && EmailClick.where.not(clicked_at: nil).count == 0
  puts "⚠️  Есть EmailClick записи, но ни один не кликнут"
  puts "   → Попробуй кликнуть по ссылке в письме"
  puts "   → Проверь логи API: docker compose logs api --tail=50 | grep -i click"
  puts ""
end

puts "✅ Диагностика завершена"
'
