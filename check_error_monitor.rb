#!/usr/bin/env ruby
# Скрипт для глубокой проверки Error Monitor
# Запуск: docker compose exec api bundle exec rails runner check_error_monitor.rb

puts "==================================================================="
puts "ГЛУБОКАЯ ПРОВЕРКА ERROR MONITOR"
puts "==================================================================="
puts ""

puts "=== 1. Проверка таблицы delivery_errors ==="
if ActiveRecord::Base.connection.table_exists?('delivery_errors')
  puts '✅ Таблица delivery_errors существует'
  puts ''
  puts 'Колонки:'
  ActiveRecord::Base.connection.columns('delivery_errors').each do |col|
    puts "  - #{col.name} (#{col.type})"
  end
else
  puts '❌ ОШИБКА: Таблица delivery_errors НЕ существует!'
  exit 1
end

puts ""
puts "=== 2. Общее количество DeliveryError ==="
total = DeliveryError.count
puts "Всего записей: #{total}"

if total > 0
  oldest = DeliveryError.order(created_at: :asc).first
  newest = DeliveryError.order(created_at: :desc).first
  puts "Самая старая: #{oldest.created_at}"
  puts "Самая новая: #{newest.created_at}"
  puts ""
  puts "Последние 10 записей:"
  DeliveryError.order(created_at: :desc).limit(10).each do |err|
    log = err.email_log
    puts "  ##{err.id}: campaign=#{err.campaign_id}, category=#{err.category}, " \
         "recipient=#{log&.recipient_masked || 'N/A'}, created=#{err.created_at.strftime('%Y-%m-%d %H:%M:%S')}"
  end
else
  puts '⚠️ WARNING: В базе НЕТ ЗАПИСЕЙ DeliveryError!'
  puts ''
  puts 'Это означает, что:'
  puts '1. Либо не было ошибок доставки'
  puts '2. Либо DeliveryError не создается при ошибках'
end

puts ""
puts "=== 3. DeliveryError за разные периоды ==="
[
  ['1 час', 1.hour],
  ['6 часов', 6.hours],
  ['24 часа', 24.hours],
  ['48 часов', 48.hours],
  ['7 дней', 7.days]
].each do |label, duration|
  count = DeliveryError.where('created_at > ?', duration.ago).count
  puts "#{label.ljust(10)}: #{count} записей"
end

puts ""
puts "=== 4. Failed EmailLog (последние 7 дней) ==="
failed = EmailLog.where(status: 'failed', created_at: 7.days.ago..Time.current)
puts "Всего failed: #{failed.count}"

with_campaign = failed.where.not(campaign_id: nil)
without_campaign = failed.where(campaign_id: nil)

puts "  С campaign_id: #{with_campaign.count}"
puts "  БЕЗ campaign_id: #{without_campaign.count}"

if with_campaign.any?
  puts ""
  puts "Проверка: есть ли DeliveryError для failed EmailLog?"
  failed_with_campaign_ids = with_campaign.pluck(:id)
  delivery_errors_count = DeliveryError.where(email_log_id: failed_with_campaign_ids).count

  puts "  Failed EmailLog с campaign_id: #{with_campaign.count}"
  puts "  DeliveryError для них: #{delivery_errors_count}"
  puts "  РАЗНИЦА (должно быть 0): #{with_campaign.count - delivery_errors_count}"

  if with_campaign.count > delivery_errors_count
    puts ""
    puts "⚠️ ПРОБЛЕМА: Есть failed EmailLog БЕЗ DeliveryError!"
    puts "Первые 5 failed EmailLog без DeliveryError:"
    with_campaign.each do |log|
      unless DeliveryError.where(email_log_id: log.id).exists?
        puts "  EmailLog ##{log.id}: campaign=#{log.campaign_id}, status=#{log.status}, " \
             "recipient=#{log.recipient_masked}, created=#{log.created_at.strftime('%Y-%m-%d %H:%M:%S')}"
      end
    end
  end
end

puts ""
puts "=== 5. Симуляция контроллера ErrorMonitorController ==="
hours = 24
errors = DeliveryError.where('created_at > ?', hours.hours.ago)
                      .includes(:email_log)
                      .order(created_at: :desc)
                      .limit(100)
                      .to_a

puts "Запрос за последние #{hours} часов: #{errors.count} записей"

stats = DeliveryError.count_by_category(window_minutes: hours * 60)
puts ""
puts "Статистика по категориям:"
if stats.empty?
  puts "  (пусто)"
else
  stats.each do |cat, count|
    puts "  #{cat}: #{count}"
  end
end

campaigns = DeliveryError.distinct.pluck(:campaign_id).compact.sort
puts ""
puts "Кампании: #{campaigns.any? ? campaigns.join(', ') : '(нет)'}"

puts ""
puts "=== 6. Создание тестовой записи DeliveryError ==="
email_log = EmailLog.where.not(campaign_id: nil).order(created_at: :desc).first

if email_log.nil?
  puts "❌ Нет EmailLog с campaign_id - невозможно создать тест"
else
  puts "EmailLog найден: ##{email_log.id}, campaign=#{email_log.campaign_id}"

  begin
    test = DeliveryError.create!(
      email_log_id: email_log.id,
      campaign_id: email_log.campaign_id,
      category: 'unknown',
      smtp_message: "TEST ERROR created at #{Time.current}",
      recipient_domain: email_log.recipient.split('@').last
    )

    puts "✅ ТЕСТОВАЯ ЗАПИСЬ СОЗДАНА!"
    puts "  ID: #{test.id}"
    puts "  Campaign: #{test.campaign_id}"
    puts "  Created: #{test.created_at}"
    puts ""
    puts "🔍 ПРОВЕРЬТЕ ERROR MONITOR:"
    puts "   https://linenarrow.com/dashboard/error_monitor"
    puts ""
    puts "   Эта запись ДОЛЖНА появиться в списке!"
    puts "   Если НЕ появилась - проблема в контроллере/view/маршрутах"
  rescue => e
    puts "❌ Ошибка создания: #{e.message}"
  end
end

puts ""
puts "==================================================================="
puts "ПРОВЕРКА ЗАВЕРШЕНА"
puts "==================================================================="
