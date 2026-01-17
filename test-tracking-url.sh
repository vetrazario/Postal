#!/bin/bash

echo "Тест tracking URL"
echo ""

cd /opt/email-sender

# Получить последний EmailClick
docker compose exec -T api bundle exec rails runner '
click = EmailClick.last

if click.nil?
  puts "❌ Нет EmailClick записей"
  exit 1
end

domain = SystemConfig.get(:domain) || "localhost"

# Генерируем tracking URL как в LinkTracker
begin
  uri = URI.parse(click.url)
  domain_parts = uri.host.to_s.split(".")
  domain_name = domain_parts[-2] || "link"
  path_slug = uri.path.to_s.split("/").reject(&:blank?).first || "page"
  slug = "#{domain_name}-#{path_slug}".downcase.gsub(/[^a-z0-9-]/, "-").gsub(/-+/, "-")[0..29]
  
  tracking_url = "https://#{domain}/go/#{slug}-#{click.token[0..15]}"
  
  puts "=== ТЕСТ TRACKING URL ==="
  puts ""
  puts "EmailClick ID: #{click.id}"
  puts "Original URL: #{click.url}"
  puts "Token (full): #{click.token}"
  puts "Token (16 chars): #{click.token[0..15]}"
  puts "Slug: #{slug}"
  puts ""
  puts "Generated tracking URL:"
  puts "  #{tracking_url}"
  puts ""
  puts "Проверь эту ссылку вручную:"
  puts "  1. Открой в браузере: #{tracking_url}"
  puts "  2. Должен редирект на: #{click.url}"
  puts "  3. В БД clicked_at должен обновиться"
  puts ""
rescue => e
  puts "❌ Error: #{e.message}"
  exit 1
end
'
