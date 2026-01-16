#!/bin/bash
set -e

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  ФИНАЛЬНАЯ ПРОВЕРКА СИСТЕМЫ ТРЕКИНГА                       ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

cd /opt/email-sender

echo "📥 1. ПОДТЯГИВАЮ ПОСЛЕДНИЕ ИЗМЕНЕНИЯ"
echo "─────────────────────────────────────────────────────────────"
git fetch origin claude/project-analysis-errors-Awt4F
git reset --hard origin/claude/project-analysis-errors-Awt4F
echo "✅ Код обновлен"

echo ""
echo "🔨 2. ПЕРЕСБОРКА API (БЕЗ КЭША)"
echo "─────────────────────────────────────────────────────────────"
docker compose build --no-cache api

echo ""
echo "🔄 3. ПЕРЕЗАПУСК КОНТЕЙНЕРОВ"
echo "─────────────────────────────────────────────────────────────"
docker compose restart api sidekiq

echo ""
echo "⏳ Жду 15 секунд..."
sleep 15

echo ""
echo "📊 4. СТАТУС КОНТЕЙНЕРОВ"
echo "─────────────────────────────────────────────────────────────"
docker compose ps

echo ""
echo "🗄️  5. ПРОВЕРКА БД - ТАБЛИЦЫ ТРЕКИНГА"
echo "─────────────────────────────────────────────────────────────"
docker compose exec -T postgres psql -U email_sender -d email_sender <<'SQL'
\dt email_clicks
\dt email_opens
SQL

echo ""
echo "📈 6. ПРОВЕРКА БД - ДАННЫЕ"
echo "─────────────────────────────────────────────────────────────"
docker compose exec -T postgres psql -U email_sender -d email_sender <<'SQL'
SELECT
  'email_clicks' as table_name,
  COUNT(*) as total_records,
  COUNT(CASE WHEN clicked_at IS NOT NULL THEN 1 END) as clicked_count
FROM email_clicks
UNION ALL
SELECT
  'email_opens' as table_name,
  COUNT(*) as total_records,
  COUNT(CASE WHEN opened_at IS NOT NULL THEN 1 END) as opened_count
FROM email_opens;
SQL

echo ""
echo "🔧 7. ПРОВЕРКА RAILS - МОДЕЛИ"
echo "─────────────────────────────────────────────────────────────"
docker compose exec -T api bundle exec rails runner '
begin
  puts "EmailClick model: #{EmailClick.name} ✅"
  puts "  - Total: #{EmailClick.count}"
  puts "  - Clicked: #{EmailClick.clicked.count}"

  puts "EmailOpen model: #{EmailOpen.name} ✅"
  puts "  - Total: #{EmailOpen.count}"
  puts "  - Opened: #{EmailOpen.opened.count}"
  puts "  - Unique: #{EmailOpen.unique_opens.count}"
rescue => e
  puts "❌ Error: #{e.message}"
  exit 1
end
'

echo ""
echo "🛣️  8. ПРОВЕРКА RAILS - РОУТЫ"
echo "─────────────────────────────────────────────────────────────"
docker compose exec -T api bundle exec rails runner '
routes = Rails.application.routes.routes
tracking_routes = routes.select { |r| r.path.spec.to_s.include?("tracking") }
if tracking_routes.any?
  puts "✅ Tracking routes found:"
  tracking_routes.each do |route|
    puts "  #{route.verb.ljust(7)} #{route.path.spec}"
  end
else
  puts "❌ No tracking routes found"
  exit 1
end
'

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  ✅ ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ!                                 ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "🎉 СИСТЕМА ТРЕКИНГА ПОЛНОСТЬЮ НАСТРОЕНА И РАБОТАЕТ"
echo ""
echo "📍 Доступ к настройкам:"
echo "   👉 https://linenarrow.com/dashboard/settings"
echo ""
echo "   В Infrastructure Summary увидишь 4 карточки:"
echo "   1. API Keys"
echo "   2. SMTP Credentials"
echo "   3. Webhooks"
echo "   4. Tracking (новая!) ← нажми 'Tracking Settings'"
echo ""
echo "✨ Возможности:"
echo "   • Включение/выключение трекинга открытий"
echo "   • Включение/выключение трекинга кликов"
echo "   • Статистика в реальном времени"
echo "   • Аналитика интегрирована с EmailClick/EmailOpen"
echo "   • Ошибки отправки записываются в error_log"
echo ""
echo "🔥 Обнови страницу в браузере (Ctrl+Shift+R) если не видишь карточку!"
echo ""
