#!/bin/bash
set -e

cd /opt/email-sender

echo "==================================================================="
echo "ОТПРАВКА ТЕСТОВОГО EMAIL ДЛЯ ПРОВЕРКИ DELIVERYERROR"
echo "==================================================================="
echo ""

echo "Отправляем email через вашу систему (Campaign API)..."
echo ""

docker compose exec -T api bundle exec rails runner "
# Найти существующую кампанию или создать тестовую
campaign_id = Campaign.order(created_at: :desc).first&.id || 'test-campaign-999'

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
puts '  1. Postal попытается отправить'
puts '  2. Gmail вернет 550 User not found'
puts '  3. Postal отправит MessageBounced/MessageHeld webhook'
puts '  4. WebhooksController создаст DeliveryError'
puts ''
puts 'Подождите 60 секунд, затем проверьте:'
puts '  docker compose exec -T api tail -n 100 /app/log/production.log | grep DeliveryError'
"

echo ""
echo "Ожидание 60 секунд для обработки..."
for i in {60..1}; do
  echo -ne "Осталось $i секунд...\r"
  sleep 1
done
echo ""

echo ""
echo "=== Проверка production.log ==="
docker compose exec -T api tail -n 200 /app/log/production.log | grep -i "DeliveryError\|MessageHeld\|MessageBounced" || echo "  (не найдено в логах)"

echo ""
echo "=== Проверка базы данных ==="
docker compose exec -T api bundle exec rails runner "
  recent = DeliveryError.where('created_at > ?', 2.minutes.ago).order(created_at: :desc)
  puts \"DeliveryError за последние 2 минуты: #{recent.count}\"

  if recent.any?
    puts ''
    puts '✅ УСПЕХ! DeliveryError созданы:'
    recent.each do |err|
      puts \"  ##{err.id}: campaign=#{err.campaign_id}, category=#{err.category}, created=#{err.created_at}\"
    end
  else
    puts ''
    puts '❌ DeliveryError НЕ создан'
    puts ''
    puts 'Проверьте:'
    puts '1. EmailLog статус'
    puts '2. production.log полностью'
    puts '3. Sidekiq логи'
  end
"

echo ""
echo "=== Проверка EmailLog ==="
docker compose exec -T api bundle exec rails runner "
  recent_logs = EmailLog.where('created_at > ?', 2.minutes.ago).order(created_at: :desc)
  puts \"EmailLog за последние 2 минуты: #{recent_logs.count}\"

  recent_logs.each do |log|
    puts \"  ##{log.id}: status=#{log.status}, campaign=#{log.campaign_id}, recipient=#{log.recipient_masked}\"
  end
"

echo ""
echo "==================================================================="
echo "ПРОВЕРКА ЗАВЕРШЕНА"
echo "==================================================================="
echo ""
echo "Если DeliveryError создан - проверьте Error Monitor:"
echo "https://linenarrow.com/dashboard/error_monitor"
echo ""
