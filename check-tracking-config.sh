#!/bin/bash

echo "Проверка настроек трекинга"
echo ""

cd /opt/email-sender

docker compose exec -T api bundle exec rails runner '
config = SystemConfig.instance

puts "=== НАСТРОЙКИ ТРЕКИНГА ==="
puts ""
puts "Domain: #{config.domain rescue "ERROR"}"
puts "Tracking domain: #{SystemConfig.get(:tracking_domain) || "не настроен (используется domain)"}"
puts ""
puts "Enable click tracking: #{SystemConfig.get(:enable_click_tracking).inspect}"
puts "Enable open tracking: #{SystemConfig.get(:enable_open_tracking).inspect}"
puts "Max tracked links: #{SystemConfig.get(:max_tracked_links) || 10}"
puts ""

# Проверим что LinkTracker.load_system_defaults вернет
puts "=== ЧТО ВИДИТ LINKTRACKER ==="
puts ""

# Симулируем что делает LinkTracker
track_clicks_setting = SystemConfig.get(:enable_click_tracking)
track_opens_setting = SystemConfig.get(:enable_open_tracking)

puts "track_clicks будет: #{track_clicks_setting != false} (значение: #{track_clicks_setting.inspect})"
puts "track_opens будет: #{track_opens_setting == true} (значение: #{track_opens_setting.inspect})"
puts ""

if track_clicks_setting == false
  puts "❌ ПРОБЛЕМА: enable_click_tracking = false"
  puts "   Ссылки НЕ будут подменяться!"
  puts ""
  puts "   Исправь:"
  puts "   1. Зайди на https://linenarrow.com/dashboard/tracking_settings"
  puts "   2. Включи галочку \"Enable Click Tracking\""
  puts "   3. Сохрани"
  puts ""
elsif track_clicks_setting.nil?
  puts "⚠️  enable_click_tracking не установлен (nil)"
  puts "   По умолчанию будет true, но лучше установить явно"
  puts ""
else
  puts "✅ enable_click_tracking = #{track_clicks_setting}"
  puts "   Ссылки ДОЛЖНЫ подменяться"
  puts ""
end
'
