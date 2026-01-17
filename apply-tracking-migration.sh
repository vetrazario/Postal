#!/bin/bash
set -e

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  ПРИМЕНЕНИЕ МИГРАЦИИ ДЛЯ НАСТРОЕК ТРЕКИНГА                 ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

cd /opt/email-sender

echo "1️⃣  Подтягиваю код с миграцией"
echo "─────────────────────────────────────────────────────────────"
git pull origin claude/project-analysis-errors-Awt4F

echo ""
echo "2️⃣  Проверяю что миграция есть"
echo "─────────────────────────────────────────────────────────────"
if [ -f "services/api/db/migrate/20260117000000_add_tracking_settings_to_system_configs.rb" ]; then
  echo "✅ Миграция найдена"
else
  echo "❌ Миграция не найдена!"
  exit 1
fi

echo ""
echo "3️⃣  Применяю миграцию"
echo "─────────────────────────────────────────────────────────────"
docker compose exec -T api bundle exec rails db:migrate

echo ""
echo "4️⃣  Проверяю что поля добавлены"
echo "─────────────────────────────────────────────────────────────"
docker compose exec -T postgres psql -U email_sender -d email_sender <<'SQL'
\d system_configs
SQL

echo ""
echo "5️⃣  Пересобираю API с новым кодом"
echo "─────────────────────────────────────────────────────────────"
docker compose build api

echo ""
echo "6️⃣  Перезапускаю контейнеры"
echo "─────────────────────────────────────────────────────────────"
docker compose restart api sidekiq

echo ""
echo "⏳ Жду 15 секунд..."
sleep 15

echo ""
echo "7️⃣  Проверяю что все работает"
echo "─────────────────────────────────────────────────────────────"
docker compose exec -T api bundle exec rails runner '
config = SystemConfig.instance
puts "SystemConfig fields:"
puts "  - enable_open_tracking: #{config.respond_to?(:enable_open_tracking)}"
puts "  - enable_click_tracking: #{config.respond_to?(:enable_click_tracking)}"
puts "  - tracking_domain: #{config.respond_to?(:tracking_domain)}"

# Test set method
begin
  SystemConfig.set(:enable_open_tracking, true)
  puts "✅ SystemConfig.set works!"
rescue => e
  puts "❌ SystemConfig.set failed: #{e.message}"
  exit 1
end
'

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  ✅ МИГРАЦИЯ ПРИМЕНЕНА УСПЕШНО!                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Теперь можешь:"
echo "  1. Очисти кэш браузера (Ctrl+Shift+R)"
echo "  2. Зайди на https://linenarrow.com/dashboard/settings"
echo "  3. Нажми 'Tracking Settings'"
echo "  4. Включи галочки - они теперь будут сохраняться!"
echo ""
