#!/bin/bash
set -e

echo "Тестирование системы логирования ошибок"
echo ""

cd /opt/email-sender

docker compose exec -T api bundle exec rails runner '
begin
  puts "=== ТЕСТ СИСТЕМЫ ЛОГИРОВАНИЯ ОШИБОК ==="
  puts ""
  
  # Проверяем модель
  puts "1. DeliveryError model: #{DeliveryError.name}"
  puts "   CATEGORIES: #{DeliveryError::CATEGORIES.join(", ")}"
  puts "   Current records: #{DeliveryError.count}"
  puts ""
  
  # Ищем EmailLog с campaign_id
  email_log = EmailLog.where.not(campaign_id: [nil, ""]).first
  
  if email_log.nil?
    puts "2. ⚠️  Нет EmailLog с campaign_id - создаю тестовый"
    
    # Создаем тестовый EmailLog
    email_log = EmailLog.create!(
      message_id: "test-#{SecureRandom.hex(8)}",
      external_message_id: "ext-#{SecureRandom.hex(8)}",
      campaign_id: "test-campaign",
      recipient: "test@example.com",
      recipient_masked: "t***@example.com",
      sender: "noreply@test.com",
      subject: "Test Email",
      status: "sent"
    )
    puts "   ✅ Создан тестовый EmailLog: #{email_log.id}"
  else
    puts "2. ✅ Найден EmailLog: #{email_log.id}"
    puts "   - campaign_id: #{email_log.campaign_id}"
    puts "   - recipient: #{email_log.recipient}"
  end
  puts ""
  
  # Тест создания DeliveryError
  puts "3. Создаю тестовый DeliveryError..."
  test_error = DeliveryError.create!(
    email_log_id: email_log.id,
    campaign_id: email_log.campaign_id,
    category: "connection",
    smtp_message: "Test error: connection timeout",
    smtp_code: "421",
    recipient_domain: email_log.recipient.split("@").last
  )
  
  puts "   ✅ DeliveryError создан: ID #{test_error.id}"
  puts "      - email_log_id: #{test_error.email_log_id}"
  puts "      - campaign_id: #{test_error.campaign_id}"
  puts "      - category: #{test_error.category}"
  puts "      - smtp_message: #{test_error.smtp_message}"
  puts "      - smtp_code: #{test_error.smtp_code}"
  puts "      - recipient_domain: #{test_error.recipient_domain}"
  puts ""
  
  # Проверяем методы модели
  puts "4. Проверяю scopes модели..."
  recent_errors = DeliveryError.recent(60).count
  puts "   - recent(60): #{recent_errors} errors"
  
  by_campaign = DeliveryError.by_campaign(email_log.campaign_id).count
  puts "   - by_campaign: #{by_campaign} errors"
  
  by_category = DeliveryError.by_category("connection").count
  puts "   - by_category(connection): #{by_category} errors"
  puts ""
  
  # Очистка
  puts "5. Очистка тестовых данных..."
  test_error.destroy!
  puts "   ✅ DeliveryError удален"
  
  if email_log.message_id.start_with?("test-")
    email_log.destroy!
    puts "   ✅ Тестовый EmailLog удален"
  end
  puts ""
  
  puts "╔════════════════════════════════════════════════════════════╗"
  puts "║  🎉 ВСЕ ТЕСТЫ ПРОЙДЕНЫ УСПЕШНО!                           ║"
  puts "╚════════════════════════════════════════════════════════════╝"
  puts ""
  puts "Система логирования ошибок работает корректно!"
  puts ""
  
rescue => e
  puts ""
  puts "❌ ERROR: #{e.class} - #{e.message}"
  puts ""
  puts "Backtrace:"
  puts e.backtrace.first(5).join("\n")
  exit 1
end
'
