#!/bin/bash
set -e

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  ФИНАЛЬНЫЙ ФИКС SYSTEMCONFIG                               ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

cd /opt/email-sender

echo "1️⃣  Подтягиваю код"
echo "─────────────────────────────────────────────────────────────"
git fetch origin claude/project-analysis-errors-Awt4F
git reset --hard origin/claude/project-analysis-errors-Awt4F

echo ""
echo "2️⃣  Проверяю что метод set есть в коде"
echo "─────────────────────────────────────────────────────────────"
if grep -q "def self.set" services/api/app/models/system_config.rb; then
  echo "✅ Метод SystemConfig.set найден в коде"
else
  echo "❌ Метод SystemConfig.set НЕ НАЙДЕН!"
  exit 1
fi

echo ""
echo "3️⃣  Останавливаю API"
echo "─────────────────────────────────────────────────────────────"
docker compose stop api

echo ""
echo "4️⃣  Удаляю старый контейнер"
echo "─────────────────────────────────────────────────────────────"
docker compose rm -f api

echo ""
echo "5️⃣  Пересборка с нуля БЕЗ КЭША"
echo "─────────────────────────────────────────────────────────────"
docker compose build --no-cache api

echo ""
echo "6️⃣  Запускаю API"
echo "─────────────────────────────────────────────────────────────"
docker compose up -d api

echo ""
echo "⏳ Жду 20 секунд..."
sleep 20

echo ""
echo "7️⃣  Проверяю что метод set загружен"
echo "─────────────────────────────────────────────────────────────"
docker compose exec -T api bundle exec rails runner '
if SystemConfig.respond_to?(:set)
  puts "✅ SystemConfig.set метод доступен"
else
  puts "❌ SystemConfig.set метод НЕ доступен"
  exit 1
end
'

echo ""
echo "8️⃣  Применяю миграцию"
echo "─────────────────────────────────────────────────────────────"
docker compose exec -T api bundle exec rails db:migrate

echo ""
echo "9️⃣  Проверяю структуру таблицы"
echo "─────────────────────────────────────────────────────────────"
docker compose exec -T postgres psql -U email_sender -d email_sender <<'SQL'
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_name = 'system_configs'
  AND column_name IN ('enable_open_tracking', 'enable_click_tracking', 'tracking_domain')
ORDER BY column_name;
SQL

echo ""
echo "🔟 Тестирую SystemConfig.set"
echo "─────────────────────────────────────────────────────────────"
docker compose exec -T api bundle exec rails runner '
begin
  # Тест 1: метод существует
  raise "set method missing" unless SystemConfig.respond_to?(:set)
  puts "✅ Test 1: SystemConfig.set method exists"

  # Тест 2: instance доступен
  config = SystemConfig.instance
  puts "✅ Test 2: SystemConfig.instance works (id: #{config.id})"

  # Тест 3: поле enable_open_tracking существует
  if config.respond_to?(:enable_open_tracking)
    puts "✅ Test 3: enable_open_tracking field exists (current: #{config.enable_open_tracking})"
  else
    puts "❌ Test 3: enable_open_tracking field MISSING"
    exit 1
  end

  # Тест 4: можем изменить значение
  old_value = config.enable_open_tracking
  SystemConfig.set(:enable_open_tracking, !old_value)
  config.reload
  if config.enable_open_tracking == !old_value
    puts "✅ Test 4: SystemConfig.set successfully changed value"
    # Верни обратно
    SystemConfig.set(:enable_open_tracking, old_value)
  else
    puts "❌ Test 4: SystemConfig.set did not change value"
    exit 1
  end

  puts ""
  puts "🎉 ВСЕ ТЕСТЫ ПРОЙДЕНЫ!"
rescue => e
  puts "❌ ERROR: #{e.class} - #{e.message}"
  puts e.backtrace.first(5).join("\n")
  exit 1
end
'

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  ✅ ВСЕ ИСПРАВЛЕНО И РАБОТАЕТ!                             ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Теперь:"
echo "  1. Очисти кэш браузера полностью"
echo "  2. Зайди на https://linenarrow.com/dashboard/settings"
echo "  3. Нажми 'Tracking Settings'"
echo "  4. Включи любую галочку - сохранится без ошибок!"
echo ""
