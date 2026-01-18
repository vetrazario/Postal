#!/bin/bash
set -e

cd /opt/email-sender

echo "==================================================================="
echo "ОТПРАВКА ТЕСТОВОГО EMAIL ДЛЯ ПРОВЕРКИ DELIVERYERROR"
echo "==================================================================="
echo ""

echo "Отправляем email через вашу систему..."
echo ""

docker compose exec -T api bundle exec rails runner "
# Взять campaign_id из существующих EmailLog
campaign_id = EmailLog.where.not(campaign_id: nil).order(created_at: :desc).first&.campaign_id || 'test-999'

puts \"Используем campaign_id: #{campaign_id}\"
puts ''

# Создать EmailLog для несуществующего получателя
log = EmailLog.create!(
  message_id: 'test-error-monitor-' + SecureRandom.hex(8),
  recipient: 'this-email-does-not-exist-999@gmail.com',
  sender: 'info@linenarrow.com',
  subject: 'Test Error Monitor',
  status: 'queued',
  campaign_id: campaign_id.to_s,
  external_message_id: '<test-' + SecureRandom.hex(8) + '@linenarrow.com>'
)

puts \"✅ EmailLog создан: ##{log.id}\"
puts \"   Campaign: #{log.campaign_id}\"
puts \"   Recipient: #{log.recipient}\"
puts ''

# Поставить в очередь SendSmtpEmailJob
email_data = {
  email_log_id: log.id,
  envelope: {
    from: 'info@linenarrow.com',
    to: 'this-email-does-not-exist-999@gmail.com'
  },
  message: {
    subject: 'Test Error Monitor',
    text: 'This is a test email to check DeliveryError creation.',
    html: '<p>This is a test email to check DeliveryError creation.</p>'
  }
}

SendSmtpEmailJob.perform_later(email_data)

puts '✅ Job поставлен в очередь Sidekiq'
puts ''
puts 'Email будет обработан через несколько секунд.'
puts 'Получатель НЕ существует, поэтому:'
puts '  1. SendSmtpEmailJob отправит через Postal'
puts '  2. Gmail вернет 550 User not found'
puts '  3. Postal отправит MessageBounced/MessageHeld webhook'
puts '  4. WebhooksController создаст DeliveryError'
puts ''
puts 'Подождите 60 секунд...'
"

echo ""
echo "Ожидание 60 секунд для обработки..."
for i in {60..1}; do
  printf "Осталось %2d секунд...\r" $i
  sleep 1
done
echo ""
echo ""

echo "=== Проверка production.log ==="
docker compose exec -T api tail -n 300 /app/log/production.log | grep -i "DeliveryError\|MessageHeld\|MessageBounced\|test-error-monitor" || echo "  (не найдено в логах)"

echo ""
echo "=== Проверка базы данных ==="
docker compose exec -T api bundle exec rails runner "
  recent = DeliveryError.where('created_at > ?', 2.minutes.ago).order(created_at: :desc)
  puts \"DeliveryError за последние 2 минуты: #{recent.count}\"

  if recent.any?
    puts ''
    puts '✅ УСПЕХ! DeliveryError созданы:'
    recent.each do |err|
      log = err.email_log
      puts \"  ##{err.id}: campaign=#{err.campaign_id}, category=#{err.category}, recipient=#{log&.recipient_masked}, created=#{err.created_at}\"
    end
  else
    puts ''
    puts '❌ DeliveryError НЕ создан'
  end
"

echo ""
echo "=== Проверка EmailLog ==="
docker compose exec -T api bundle exec rails runner "
  recent_logs = EmailLog.where('created_at > ?', 2.minutes.ago).order(created_at: :desc)
  puts \"EmailLog за последние 2 минуты: #{recent_logs.count}\"
  puts ''

  recent_logs.each do |log|
    has_delivery_error = DeliveryError.where(email_log_id: log.id).exists?
    puts \"  ##{log.id}:\"
    puts \"    Status: #{log.status}\"
    puts \"    Campaign: #{log.campaign_id}\"
    puts \"    Recipient: #{log.recipient_masked}\"
    puts \"    Has DeliveryError: #{has_delivery_error}\"
    puts \"    postal_message_id: #{log.postal_message_id.inspect}\"
    puts ''
  end
"

echo ""
echo "=== Проверка Sidekiq логов ==="
docker compose logs --tail=100 sidekiq | grep -i "SendSmtpEmailJob\|test-error-monitor" || echo "  (не найдено)"

echo ""
echo "==================================================================="
echo "ПРОВЕРКА ЗАВЕРШЕНА"
echo "==================================================================="
echo ""
echo "Если DeliveryError создан - проверьте Error Monitor:"
echo "https://linenarrow.com/dashboard/error_monitor"
echo ""
echo "Если НЕ создан, проверьте полный production.log:"
echo "docker compose exec -T api tail -n 500 /app/log/production.log"
echo ""
