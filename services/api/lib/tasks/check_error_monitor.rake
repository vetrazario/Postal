namespace :error_monitor do
  desc "Deep check of Error Monitor system"
  task deep_check: :environment do
    puts "==================================================================="
    puts "ГЛУБОКАЯ ПРОВЕРКА ERROR MONITOR"
    puts "==================================================================="
    puts ""

    puts "=== 1. Проверка таблицы delivery_errors ==="
    if ActiveRecord::Base.connection.table_exists?('delivery_errors')
      puts '✅ Таблица delivery_errors существует'
      puts ''
      puts 'Колонки таблицы:'
      ActiveRecord::Base.connection.columns('delivery_errors').each do |col|
        puts "  - #{col.name} (#{col.type})"
      end
    else
      puts '❌ ОШИБКА: Таблица delivery_errors НЕ существует!'
      next
    end

    puts ""
    puts "=== 2. Проверка модели DeliveryError ==="
    puts "DeliveryError class: #{DeliveryError.name}"
    puts "Table name: #{DeliveryError.table_name}"
    puts "Primary key: #{DeliveryError.primary_key}"
    puts ''
    puts 'CATEGORIES:'
    DeliveryError::CATEGORIES.each { |cat| puts "  - #{cat}" }

    puts ""
    puts "=== 3. Общее количество DeliveryError записей (ВСЕ ВРЕМЯ) ==="
    total = DeliveryError.count
    puts "Всего DeliveryError записей: #{total}"

    if total > 0
      oldest = DeliveryError.order(created_at: :asc).first
      newest = DeliveryError.order(created_at: :desc).first
      puts "Самая старая запись: #{oldest.created_at}"
      puts "Самая новая запись: #{newest.created_at}"
      puts ""
      puts "Последние 5 записей:"
      DeliveryError.order(created_at: :desc).limit(5).each do |err|
        puts "  ##{err.id}: campaign=#{err.campaign_id}, category=#{err.category}, created=#{err.created_at}"
      end
    else
      puts '⚠️ WARNING: НЕТ ЗАПИСЕЙ DeliveryError В БАЗЕ ДАННЫХ!'
    end

    puts ""
    puts "=== 4. DeliveryError за последние периоды ==="
    periods = {
      '1 час' => 1.hour.ago,
      '6 часов' => 6.hours.ago,
      '24 часа' => 24.hours.ago,
      '48 часов' => 48.hours.ago,
      '7 дней' => 7.days.ago,
      '30 дней' => 30.days.ago
    }

    periods.each do |label, time|
      count = DeliveryError.where('created_at > ?', time).count
      puts "#{label}: #{count} записей"
    end

    puts ""
    puts "=== 5. Failed EmailLog записи (за последние 7 дней) ==="
    failed = EmailLog.where(status: 'failed', created_at: 7.days.ago..Time.current)
    puts "Failed EmailLog: #{failed.count}"

    with_campaign = failed.where.not(campaign_id: nil).count
    without_campaign = failed.where(campaign_id: nil).count

    puts "  - С campaign_id: #{with_campaign}"
    puts "  - БЕЗ campaign_id: #{without_campaign}"
    puts ''

    if with_campaign > 0
      puts 'Первые 5 failed EmailLog с campaign_id:'
      failed.where.not(campaign_id: nil).limit(5).each do |log|
        has_error = DeliveryError.where(email_log_id: log.id).exists?
        puts "  EmailLog ##{log.id}: campaign=#{log.campaign_id}, has_DeliveryError=#{has_error}, created=#{log.created_at}"
      end
    end

    puts ""
    puts "=== 6. Проверка контроллера Error Monitor (симуляция) ==="
    hours = 24

    errors = DeliveryError.all
    errors = errors.where('created_at > ?', hours.hours.ago)
    errors_list = errors.includes(:email_log).order(created_at: :desc).limit(100).to_a

    puts "Запрос: DeliveryError за последние #{hours} часов"
    puts "Результат: #{errors_list.count} записей"
    puts ''

    stats = DeliveryError.count_by_category(window_minutes: hours * 60)
    puts 'Статистика по категориям:'
    if stats.empty?
      puts '  (пусто)'
    else
      stats.each do |cat, count|
        puts "  #{cat}: #{count}"
      end
    end

    campaigns = DeliveryError.distinct.pluck(:campaign_id).compact.sort
    puts ''
    puts "Кампании с ошибками: #{campaigns.inspect}"

    puts ""
    puts "=== 7. Попытка вручную создать тестовую DeliveryError ==="
    email_log = EmailLog.where.not(campaign_id: nil).order(created_at: :desc).first

    if email_log.nil?
      puts '❌ ПРОБЛЕМА: Нет EmailLog с campaign_id!'
    else
      puts "Найден EmailLog: id=#{email_log.id}, campaign_id=#{email_log.campaign_id}, recipient=#{email_log.recipient_masked}"

      begin
        test_error = DeliveryError.create!(
          email_log_id: email_log.id,
          campaign_id: email_log.campaign_id,
          category: 'unknown',
          smtp_message: 'TEST ERROR - created by diagnostic script at ' + Time.current.to_s,
          recipient_domain: email_log.recipient.split('@').last
        )
        puts "✅ Тестовая запись создана: DeliveryError ##{test_error.id}"
        puts "   Campaign: #{test_error.campaign_id}"
        puts "   Создана: #{test_error.created_at}"
        puts ""
        puts "   🔍 Проверьте Error Monitor по адресу:"
        puts "   https://linenarrow.com/dashboard/error_monitor"
        puts "   Эта запись должна появиться в списке!"
      rescue => e
        puts "❌ ОШИБКА при создании: #{e.class.name}: #{e.message}"
        puts e.backtrace.first(5).join("\n")
      end
    end

    puts ""
    puts "==================================================================="
    puts "✅ ПРОВЕРКА ЗАВЕРШЕНА"
    puts "==================================================================="
  end

  desc "Create test DeliveryError"
  task create_test: :environment do
    puts "Создание тестовой записи DeliveryError..."

    email_log = EmailLog.where.not(campaign_id: nil).order(created_at: :desc).first

    if email_log.nil?
      puts "❌ Нет EmailLog с campaign_id"
      next
    end

    test_error = DeliveryError.create!(
      email_log_id: email_log.id,
      campaign_id: email_log.campaign_id,
      category: 'unknown',
      smtp_message: 'TEST ERROR - created at ' + Time.current.to_s,
      recipient_domain: email_log.recipient.split('@').last
    )

    puts "✅ Создана тестовая DeliveryError ##{test_error.id}"
    puts "Campaign: #{test_error.campaign_id}"
    puts "Created: #{test_error.created_at}"
  end
end
