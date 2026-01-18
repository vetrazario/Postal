#!/bin/bash
set -e

cd /home/user/Postal

echo "==================================================================="
echo "ГЛУБОКАЯ ПРОВЕРКА ERROR MONITOR"
echo "==================================================================="
echo ""

echo "=== 1. Проверка таблицы delivery_errors ==="
docker compose exec -T api bundle exec rails runner "
  puts 'Проверка существования таблицы delivery_errors...'
  if ActiveRecord::Base.connection.table_exists?('delivery_errors')
    puts '✅ Таблица delivery_errors существует'
    puts ''
    puts 'Колонки таблицы:'
    ActiveRecord::Base.connection.columns('delivery_errors').each do |col|
      puts \"  - #{col.name} (#{col.type})\"
    end
  else
    puts '❌ ОШИБКА: Таблица delivery_errors НЕ существует!'
    exit 1
  end
" || exit 1

echo ""
echo "=== 2. Проверка модели DeliveryError ==="
docker compose exec -T api bundle exec rails runner "
  puts 'Проверка модели DeliveryError...'
  puts \"DeliveryError class: #{DeliveryError.name}\"
  puts \"Table name: #{DeliveryError.table_name}\"
  puts \"Primary key: #{DeliveryError.primary_key}\"
  puts ''
  puts 'CATEGORIES:'
  DeliveryError::CATEGORIES.each { |cat| puts \"  - #{cat}\" }
"

echo ""
echo "=== 3. Общее количество DeliveryError записей (ВСЕ ВРЕМЯ) ==="
docker compose exec -T api bundle exec rails runner "
  total = DeliveryError.count
  puts \"Всего DeliveryError записей: #{total}\"

  if total > 0
    oldest = DeliveryError.order(created_at: :asc).first
    newest = DeliveryError.order(created_at: :desc).first
    puts \"Самая старая запись: #{oldest.created_at}\"
    puts \"Самая новая запись: #{newest.created_at}\"
  else
    puts '⚠️ WARNING: НЕТ ЗАПИСЕЙ DeliveryError В БАЗЕ ДАННЫХ!'
  end
"

echo ""
echo "=== 4. DeliveryError за последние периоды ==="
docker compose exec -T api bundle exec rails runner "
  periods = {
    '1 час' => 1.hour.ago,
    '6 часов' => 6.hours.ago,
    '24 часа' => 24.hours.ago,
    '48 часов' => 48.hours.ago,
    '7 дней' => 7.days.ago,
    '30 дней' => 30.days.ago,
    'Все время' => 100.years.ago
  }

  periods.each do |label, time|
    count = DeliveryError.where('created_at > ?', time).count
    puts \"#{label}: #{count} записей\"
  end
"

echo ""
echo "=== 5. Failed EmailLog записи (за последние 7 дней) ==="
docker compose exec -T api bundle exec rails runner "
  failed = EmailLog.where(status: 'failed', created_at: 7.days.ago..Time.current)
  puts \"Failed EmailLog: #{failed.count}\"

  with_campaign = failed.where.not(campaign_id: nil).count
  without_campaign = failed.where(campaign_id: nil).count

  puts \"  - С campaign_id: #{with_campaign}\"
  puts \"  - БЕЗ campaign_id: #{without_campaign}\"
  puts ''

  if with_campaign > 0
    puts 'Первые 5 failed EmailLog с campaign_id:'
    failed.where.not(campaign_id: nil).limit(5).each do |log|
      has_error = DeliveryError.where(email_log_id: log.id).exists?
      puts \"  EmailLog ##{log.id}: campaign=#{log.campaign_id}, has_DeliveryError=#{has_error}, created=#{log.created_at}\"
    end
  end
"

echo ""
echo "=== 6. Проверка контроллера Error Monitor ==="
docker compose exec -T api bundle exec rails runner "
  # Симулировать запрос к контроллеру
  puts 'Получение данных как в контроллере ErrorMonitorController#index...'
  hours = 24

  errors = DeliveryError.all
  errors = errors.where('created_at > ?', hours.hours.ago)
  errors = errors.includes(:email_log).order(created_at: :desc).limit(100)

  puts \"Запрос: DeliveryError за последние #{hours} часов\"
  puts \"Результат: #{errors.count} записей\"
  puts ''

  stats = DeliveryError.count_by_category(window_minutes: hours * 60)
  puts 'Статистика по категориям:'
  if stats.empty?
    puts '  (пусто)'
  else
    stats.each do |cat, count|
      puts \"  #{cat}: #{count}\"
    end
  end

  campaigns = DeliveryError.distinct.pluck(:campaign_id).compact.sort
  puts ''
  puts \"Кампании с ошибками: #{campaigns.inspect}\"
"

echo ""
echo "=== 7. Проверка логов создания DeliveryError ==="
echo "Ищем записи о создании DeliveryError в логах Sidekiq и API..."
docker compose logs --tail=1000 sidekiq api 2>/dev/null | grep -E "DeliveryError (created|NOT created)" | tail -n 30 || echo "  (логи не найдены)"

echo ""
echo "=== 8. Попытка вручную создать DeliveryError ==="
docker compose exec -T api bundle exec rails runner "
  puts 'Попытка создать тестовую запись DeliveryError...'

  # Найти любой EmailLog с campaign_id
  email_log = EmailLog.where.not(campaign_id: nil).first

  if email_log.nil?
    puts '❌ ПРОБЛЕМА: Нет EmailLog с campaign_id!'
    puts 'Попытка найти хоть какой-то EmailLog...'
    email_log = EmailLog.first
    if email_log.nil?
      puts '❌ КРИТИЧНО: Нет EmailLog записей вообще!'
      exit 1
    end
  end

  puts \"Найден EmailLog: id=#{email_log.id}, campaign_id=#{email_log.campaign_id.inspect}, recipient=#{email_log.recipient_masked}\"

  if email_log.campaign_id.nil?
    puts '❌ У найденного EmailLog нет campaign_id - создание невозможно'
  else
    begin
      test_error = DeliveryError.create!(
        email_log_id: email_log.id,
        campaign_id: email_log.campaign_id,
        category: 'unknown',
        smtp_message: 'TEST ERROR - created by diagnostic script',
        recipient_domain: email_log.recipient.split('@').last
      )
      puts \"✅ Тестовая запись создана: DeliveryError ##{test_error.id}\"
      puts '   Проверьте Error Monitor - эта запись должна появиться!'
      puts \"   ID записи: #{test_error.id}\"
      puts \"   Campaign: #{test_error.campaign_id}\"
      puts \"   Создана: #{test_error.created_at}\"
    rescue => e
      puts \"❌ ОШИБКА при создании: #{e.class.name}: #{e.message}\"
      puts e.backtrace.first(3).join(\"\n\")
    end
  end
"

echo ""
echo "==================================================================="
echo "✅ ПРОВЕРКА ЗАВЕРШЕНА"
echo "==================================================================="
echo ""
echo "Если DeliveryError записей НЕТ или их очень мало - проблема в том,"
echo "что они не создаются при ошибках отправки."
echo ""
echo "Если DeliveryError записи ЕСТЬ, но Error Monitor пустой - проблема"
echo "в контроллере или view."
echo ""
