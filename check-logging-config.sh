#!/bin/bash
set -e

cd /opt/email-sender

echo "==================================================================="
echo "ПРОВЕРКА КОНФИГУРАЦИИ ЛОГИРОВАНИЯ"
echo "==================================================================="
echo ""

echo "=== 1. Уровень логирования Rails ==="
docker compose exec -T api bundle exec rails runner "
  puts \"Rails environment: #{Rails.env}\"
  puts \"Logger level: #{Rails.logger.level}\"
  puts \"Logger level name: #{ActiveSupport::Logger.const_get('Severity::' + %w[DEBUG INFO WARN ERROR FATAL UNKNOWN][Rails.logger.level])}\"
  puts ''
  puts 'Level codes:'
  puts '  0 = DEBUG'
  puts '  1 = INFO'
  puts '  2 = WARN'
  puts '  3 = ERROR'
  puts '  4 = FATAL'
  puts ''

  if Rails.logger.level <= 1
    puts '✅ INFO логирование включено (level <= 1)'
  else
    puts '❌ INFO логирование ВЫКЛЮЧЕНО (level > 1)'
    puts '   Webhook логи НЕ будут писаться!'
  end
"

echo ""
echo "=== 2. Тест логирования ==="
docker compose exec -T api bundle exec rails runner "
  puts 'Тестируем логирование на разных уровнях...'
  puts ''

  Rails.logger.debug '[TEST] DEBUG level log - should only show if level=0'
  Rails.logger.info '[TEST] INFO level log - should show if level<=1'
  Rails.logger.warn '[TEST] WARN level log - should show if level<=2'
  Rails.logger.error '[TEST] ERROR level log - should show if level<=3'

  puts ''
  puts 'Проверьте логи API командой:'
  puts '  docker compose logs --tail=20 api | grep TEST'
"

echo ""
echo "Ждем 2 секунды для записи логов..."
sleep 2

echo ""
echo "=== 3. Проверка тестовых логов ==="
docker compose logs --tail=50 api | grep "\[TEST\]" || echo "  ❌ Тестовые логи НЕ НАЙДЕНЫ! Логирование не работает!"

echo ""
echo "=== 4. Проверка config/environments/production.rb ==="
docker compose exec -T api bash -c "grep -n 'config.log_level' config/environments/production.rb" || echo "  (log_level не задан явно - используется дефолт)"

echo ""
echo "=== 5. Проверка наличия логов вообще ==="
echo "Последние 20 строк логов API:"
docker compose logs --tail=20 api

echo ""
echo "==================================================================="
echo "ПРОВЕРКА ЗАВЕРШЕНА"
echo "==================================================================="
echo ""
