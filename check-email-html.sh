#!/bin/bash

echo "Проверка HTML письма с трекингом"
echo ""

cd /opt/email-sender

docker compose exec -T api bundle exec rails runner '
# Найдем последний EmailLog
email_log = EmailLog.order(created_at: :desc).first

if email_log.nil?
  puts "❌ Нет EmailLog записей"
  exit 1
end

puts "Последний EmailLog: ##{email_log.id}"
puts "Campaign: #{email_log.campaign_id}"
puts "Recipient: #{email_log.recipient}"
puts "Status: #{email_log.status}"
puts ""

# Проверим что в status_details если есть
if email_log.status_details.present?
  puts "Status details:"
  puts email_log.status_details.inspect
  puts ""
end

# Найдем EmailClick записи для этого лога
clicks = EmailClick.where(email_log_id: email_log.id)
puts "EmailClick записей для этого письма: #{clicks.count}"

if clicks.any?
  puts ""
  puts "Tracking URLs в этом письме:"
  clicks.each do |click|
    domain = SystemConfig.get(:domain) || "localhost"
    
    # Генерируем slug
    begin
      uri = URI.parse(click.url)
      domain_parts = uri.host.to_s.split(".")
      domain_name = domain_parts[-2] || "link"
      path_slug = uri.path.to_s.split("/").reject(&:blank?).first || "page"
      slug = "#{domain_name}-#{path_slug}".downcase.gsub(/[^a-z0-9-]/, "-").gsub(/-+/, "-")[0..29]
      
      tracking_url = "https://#{domain}/go/#{slug}-#{click.token[0..15]}"
      puts "  Original: #{click.url}"
      puts "  Tracking: #{tracking_url}"
      puts "  Clicked: #{click.clicked_at.present? ? "Yes" : "No"}"
      puts ""
    rescue => e
      puts "  Error: #{e.message}"
    end
  end
end

# Проверим open tracking
opens = EmailOpen.where(email_log_id: email_log.id)
puts "EmailOpen записей для этого письма: #{opens.count}"

if opens.any?
  opens.each do |open|
    domain = SystemConfig.get(:domain) || "localhost"
    pixel_url = "https://#{domain}/t/o/#{open.token}.gif"
    puts "  Pixel URL: #{pixel_url}"
    puts "  Opened: #{open.opened_at.present? ? "Yes at #{open.opened_at}" : "No"}"
  end
end
'
