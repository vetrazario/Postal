#!/bin/bash

echo "Проверка HTML который был отправлен в Postal"
echo ""

cd /opt/email-sender

docker compose exec -T api bundle exec rails runner '
# Найдем последний EmailLog с EmailClick записями
email_log = EmailLog.joins("LEFT JOIN email_clicks ON email_clicks.email_log_id = email_logs.id")
                    .where.not("email_clicks.id": nil)
                    .order("email_logs.created_at DESC")
                    .first

if email_log.nil?
  puts "❌ Нет EmailLog с EmailClick записями"
  exit 1
end

puts "=== ПРОВЕРКА HTML В ПИСЬМЕ ==="
puts ""
puts "EmailLog ##{email_log.id}"
puts "Campaign: #{email_log.campaign_id}"
puts "Recipient: #{email_log.recipient}"
puts "Status: #{email_log.status}"
puts "Created: #{email_log.created_at}"
puts ""

# Найдем EmailClick для этого письма
clicks = EmailClick.where(email_log_id: email_log.id)
puts "EmailClick записей: #{clicks.count}"
puts ""

if clicks.any?
  puts "Tracking URLs которые ДОЛЖНЫ быть в письме:"
  clicks.each_with_index do |click, i|
    domain = SystemConfig.get(:domain) || "localhost"
    
    begin
      uri = URI.parse(click.url)
      domain_parts = uri.host.to_s.split(".")
      domain_name = domain_parts[-2] || "link"
      path_slug = uri.path.to_s.split("/").reject(&:blank?).first || "page"
      slug = "#{domain_name}-#{path_slug}".downcase.gsub(/[^a-z0-9-]/, "-").gsub(/-+/, "-")[0..29]
      
      tracking_url = "https://#{domain}/go/#{slug}-#{click.token[0..15]}"
      
      puts "#{i+1}. Original: #{click.url}"
      puts "   Tracking: #{tracking_url}"
      puts ""
    rescue => e
      puts "#{i+1}. Error: #{e.message}"
    end
  end
end

puts "─────────────────────────────────────────────────────────────"
puts ""
puts "ВАЖНО: Открой письмо в почте и посмотри на ссылку:"
puts "  1. Нажми правой кнопкой на ссылке -> Копировать адрес ссылки"
puts "  2. Вставь URL сюда и сравни"
puts ""
puts "Если URL в письме = https://www.youtube.com/"
puts "  ❌ Значит ссылки НЕ подменяются (LinkTracker не работает)"
puts ""
puts "Если URL в письме = https://linenarrow.com/go/..."
puts "  ✅ Подмена работает, но нужно проверить почему клик не доходит"
puts ""
'
