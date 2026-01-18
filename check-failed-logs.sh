#!/bin/bash
set -e

cd /opt/email-sender

echo "==================================================================="
echo "ПРОВЕРКА FAILED EMAILLOGS"
echo "==================================================================="
echo ""

echo "=== 1. Детали failed EmailLog (последние 7 дней) ==="
docker compose exec -T api bundle exec rails runner "
  failed = EmailLog.where(status: 'failed', created_at: 7.days.ago..Time.current)
                    .order(created_at: :desc)

  puts \"Всего failed EmailLog: #{failed.count}\"
  puts ''
  puts 'Первые 10 failed EmailLog:'
  puts ''

  failed.limit(10).each do |log|
    has_delivery_error = DeliveryError.where(email_log_id: log.id).exists?

    puts \"EmailLog ##{log.id}:\"
    puts \"  Campaign ID: #{log.campaign_id.inspect}\"
    puts \"  Status: #{log.status}\"
    puts \"  Recipient: #{log.recipient_masked}\"
    puts \"  Created: #{log.created_at}\"
    puts \"  Status Details: #{log.status_details.inspect}\"
    puts \"  Has DeliveryError: #{has_delivery_error}\"
    puts ''
  end
"

echo ""
echo "=== 2. Проверка логов создания DeliveryError ==="
echo "Ищем в логах Sidekiq..."
docker compose logs --tail=500 sidekiq | grep -i "DeliveryError" | tail -n 30 || echo "  (нет записей о DeliveryError в логах Sidekiq)"

echo ""
echo "Ищем в логах API..."
docker compose logs --tail=500 api | grep -i "DeliveryError" | tail -n 30 || echo "  (нет записей о DeliveryError в логах API)"

echo ""
echo "=== 3. Проверка наличия campaign_id в failed logs ==="
docker compose exec -T api bundle exec rails runner "
  failed = EmailLog.where(status: 'failed', created_at: 7.days.ago..Time.current)

  puts 'Campaign IDs в failed EmailLog:'
  campaign_ids = failed.pluck(:campaign_id).compact.uniq
  if campaign_ids.any?
    campaign_ids.each { |cid| puts \"  - #{cid}\" }
  else
    puts '  (нет campaign_id)'
  end
"

echo ""
echo "=== 4. Проверка SendSmtpEmailJob ==="
docker compose exec -T api bundle exec rails runner "
  puts 'Проверка кода SendSmtpEmailJob...'

  # Проверка, есть ли код создания DeliveryError
  code = File.read('app/jobs/send_smtp_email_job.rb')

  if code.include?('DeliveryError.create')
    puts '✅ В SendSmtpEmailJob есть код создания DeliveryError'

    if code.include?('if email_log.campaign_id.present?')
      puts '✅ Есть проверка campaign_id.present?'
    else
      puts '⚠️ НЕТ проверки campaign_id.present? - может падать!'
    end
  else
    puts '❌ В SendSmtpEmailJob НЕТ кода создания DeliveryError!'
  end
"

echo ""
echo "=== 5. Проверка webhooks_controller ==="
docker compose exec -T api bundle exec rails runner "
  puts 'Проверка кода webhooks_controller...'

  code = File.read('app/controllers/api/v1/webhooks_controller.rb')

  if code.include?('DeliveryError.create')
    puts '✅ В webhooks_controller есть код создания DeliveryError'
  else
    puts '❌ В webhooks_controller НЕТ кода создания DeliveryError!'
  end
"

echo ""
echo "=== 6. Попытка вручную создать DeliveryError для failed EmailLog ==="
docker compose exec -T api bundle exec rails runner "
  # Найти failed EmailLog БЕЗ DeliveryError
  failed_log = EmailLog.where(status: 'failed')
                       .where.not(campaign_id: nil)
                       .where('created_at > ?', 7.days.ago)
                       .find { |log| !DeliveryError.where(email_log_id: log.id).exists? }

  if failed_log.nil?
    puts '✅ Все failed EmailLog уже имеют DeliveryError'
  else
    puts \"Найден failed EmailLog БЕЗ DeliveryError: ##{failed_log.id}\"
    puts \"  Campaign: #{failed_log.campaign_id}\"
    puts \"  Status: #{failed_log.status}\"
    puts \"  Created: #{failed_log.created_at}\"
    puts ''
    puts 'Попытка создать DeliveryError вручную...'

    begin
      error = DeliveryError.create!(
        email_log_id: failed_log.id,
        campaign_id: failed_log.campaign_id,
        category: 'unknown',
        smtp_message: 'Manually created for failed EmailLog (diagnostic)',
        recipient_domain: failed_log.recipient.split('@').last
      )

      puts \"✅ DeliveryError создан: ##{error.id}\"
      puts ''
      puts 'Это доказывает, что создание работает вручную.'
      puts 'Проблема: код НЕ вызывается автоматически при ошибках!'
    rescue => e
      puts \"❌ Ошибка: #{e.message}\"
    end
  end
"

echo ""
echo "==================================================================="
echo "ПРОВЕРКА ЗАВЕРШЕНА"
echo "==================================================================="
echo ""
