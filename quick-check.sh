#!/bin/bash
set -e

cd /opt/email-sender

echo "==================================================================="
echo "БЫСТРАЯ ПРОВЕРКА ERROR MONITOR"
echo "==================================================================="
echo ""

echo "=== 1. Общее количество DeliveryError ==="
docker compose exec -T api bundle exec rails runner "
  total = DeliveryError.count
  puts \"Всего DeliveryError записей: #{total}\"

  if total > 0
    oldest = DeliveryError.order(created_at: :asc).first
    newest = DeliveryError.order(created_at: :desc).first
    puts \"Самая старая: #{oldest.created_at}\"
    puts \"Самая новая: #{newest.created_at}\"
    puts ''
    puts 'Последние 5 записей:'
    DeliveryError.order(created_at: :desc).limit(5).each do |err|
      log = err.email_log
      puts \"  ##{err.id}: campaign=#{err.campaign_id}, category=#{err.category}, created=#{err.created_at.strftime('%Y-%m-%d %H:%M:%S')}\"
    end
  else
    puts '❌ В базе НЕТ ЗАПИСЕЙ DeliveryError!'
  end
"

echo ""
echo "=== 2. DeliveryError за разные периоды ==="
docker compose exec -T api bundle exec rails runner "
  [
    ['1 час', 1.hour],
    ['6 часов', 6.hours],
    ['24 часа', 24.hours],
    ['48 часов', 48.hours],
    ['7 дней', 7.days]
  ].each do |label, duration|
    count = DeliveryError.where('created_at > ?', duration.ago).count
    puts \"#{label.ljust(10)}: #{count} записей\"
  end
"

echo ""
echo "=== 3. Failed EmailLog (последние 7 дней) ==="
docker compose exec -T api bundle exec rails runner "
  failed = EmailLog.where(status: 'failed', created_at: 7.days.ago..Time.current)
  puts \"Всего failed: #{failed.count}\"

  with_campaign = failed.where.not(campaign_id: nil)
  without_campaign = failed.where(campaign_id: nil)

  puts \"  С campaign_id: #{with_campaign.count}\"
  puts \"  БЕЗ campaign_id: #{without_campaign.count}\"

  if with_campaign.any?
    puts ''
    failed_with_campaign_ids = with_campaign.pluck(:id)
    delivery_errors_count = DeliveryError.where(email_log_id: failed_with_campaign_ids).count

    puts \"Проверка: есть ли DeliveryError для failed EmailLog?\"
    puts \"  Failed EmailLog с campaign_id: #{with_campaign.count}\"
    puts \"  DeliveryError для них: #{delivery_errors_count}\"
    puts \"  РАЗНИЦА (должно быть 0): #{with_campaign.count - delivery_errors_count}\"

    if with_campaign.count > delivery_errors_count
      puts ''
      puts '⚠️ ПРОБЛЕМА: Есть failed EmailLog БЕЗ DeliveryError!'
    end
  end
"

echo ""
echo "=== 4. Создание тестовой DeliveryError ==="
docker compose exec -T api bundle exec rails runner "
  email_log = EmailLog.where.not(campaign_id: nil).order(created_at: :desc).first

  if email_log.nil?
    puts '❌ Нет EmailLog с campaign_id - невозможно создать тест'
  else
    puts \"EmailLog найден: ##{email_log.id}, campaign=#{email_log.campaign_id}\"

    begin
      test = DeliveryError.create!(
        email_log_id: email_log.id,
        campaign_id: email_log.campaign_id,
        category: 'unknown',
        smtp_message: \"TEST ERROR created at #{Time.current}\",
        recipient_domain: email_log.recipient.split('@').last
      )

      puts ''
      puts '✅ ТЕСТОВАЯ ЗАПИСЬ СОЗДАНА!'
      puts \"  ID: #{test.id}\"
      puts \"  Campaign: #{test.campaign_id}\"
      puts \"  Created: #{test.created_at}\"
      puts ''
      puts '🔍 ПРОВЕРЬТЕ ERROR MONITOR:'
      puts '   https://linenarrow.com/dashboard/error_monitor'
      puts ''
      puts '   Эта запись ДОЛЖНА появиться в списке!'
      puts '   Hard Refresh: Ctrl+Shift+R'
    rescue => e
      puts \"❌ Ошибка создания: #{e.message}\"
    end
  end
"

echo ""
echo "==================================================================="
echo "ПРОВЕРКА ЗАВЕРШЕНА"
echo "==================================================================="
echo ""
echo "Теперь откройте Error Monitor и проверьте, появилась ли тестовая запись:"
echo "https://linenarrow.com/dashboard/error_monitor"
echo ""
