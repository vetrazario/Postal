#!/bin/bash
set -e

cd /opt/email-sender

echo "==================================================================="
echo "ПРОВЕРКА POSTAL_MESSAGE_ID"
echo "==================================================================="
echo ""

echo "=== 1. Проверка колонки postal_message_id в email_logs ==="
docker compose exec -T api bundle exec rails runner "
  columns = ActiveRecord::Base.connection.columns('email_logs').map(&:name)
  puts 'Колонки таблицы email_logs:'
  columns.each { |col| puts \"  - #{col}\" }
  puts ''

  if columns.include?('postal_message_id')
    puts '✅ Колонка postal_message_id существует'
  else
    puts '❌ Колонка postal_message_id НЕ существует!'
    puts '   Это КРИТИЧЕСКАЯ ПРОБЛЕМА - webhooks не смогут найти EmailLog!'
  end
"

echo ""
echo "=== 2. Проверка заполнения postal_message_id в failed EmailLog ==="
docker compose exec -T api bundle exec rails runner "
  failed = EmailLog.where(status: 'failed').order(created_at: :desc).limit(10)

  puts 'Проверка failed EmailLog:'
  failed.each do |log|
    postal_msg_id = log.try(:postal_message_id)
    has_value = postal_msg_id.present?

    puts \"EmailLog ##{log.id}:\"
    puts \"  postal_message_id: #{postal_msg_id.inspect}\"
    puts \"  Заполнено: #{has_value ? '✅' : '❌'}\"

    # Проверить status_details
    if log.status_details.is_a?(Hash)
      webhook_message_id = log.status_details.dig('message', 'id')
      puts \"  Webhook message.id: #{webhook_message_id.inspect}\"
    end
    puts ''
  end
"

echo ""
echo "=== 3. Проверка как EmailLog находит webhook ==="
docker compose exec -T api bundle exec rails runner "
  # Взять последний failed EmailLog
  log = EmailLog.where(status: 'failed').order(created_at: :desc).first

  if log.nil?
    puts '❌ Нет failed EmailLog'
    exit 0
  end

  puts \"Тестируем поиск для EmailLog ##{log.id}\"
  puts ''

  # Извлечь postal message id из status_details (как webhook передает)
  if log.status_details.is_a?(Hash)
    webhook_msg_id = log.status_details.dig('message', 'id')&.to_s
    puts \"Webhook message.id из status_details: #{webhook_msg_id.inspect}\"
    puts ''

    if webhook_msg_id
      # Попробовать найти как webhook
      found = EmailLog.find_by(postal_message_id: webhook_msg_id)

      if found
        puts \"✅ EmailLog найден по postal_message_id=#{webhook_msg_id}\"
        puts \"   Найден EmailLog ##{found.id}\"
      else
        puts \"❌ EmailLog НЕ НАЙДЕН по postal_message_id=#{webhook_msg_id}\"
        puts '   Это объясняет, почему DeliveryError не создается!'
        puts ''
        puts 'Webhook получает message.id и ищет:'
        puts \"  EmailLog.find_by(postal_message_id: '#{webhook_msg_id}')\"
        puts '  Но не находит, потому что postal_message_id не заполнен!'
      end
    end
  else
    puts '⚠️ status_details не Hash или пустой'
  end
"

echo ""
echo "=== 4. Проверка где заполняется postal_message_id ==="
docker compose exec -T api bundle exec rails runner "
  puts 'Проверка кода SendSmtpEmailJob...'
  code = File.read('app/jobs/send_smtp_email_job.rb')

  if code.include?('postal_message_id')
    puts '✅ В SendSmtpEmailJob есть код для postal_message_id'

    # Показать где заполняется
    lines = code.split(\"\n\")
    lines.each_with_index do |line, idx|
      if line.include?('postal_message_id')
        puts \"  Строка #{idx + 1}: #{line.strip}\"
      end
    end
  else
    puts '❌ В SendSmtpEmailJob НЕТ кода для postal_message_id!'
    puts '   EmailLog создается БЕЗ postal_message_id!'
  end
"

echo ""
echo "=== 5. Проверка alternative message_id полей ==="
docker compose exec -T api bundle exec rails runner "
  log = EmailLog.where(status: 'failed').order(created_at: :desc).first

  if log
    puts \"EmailLog ##{log.id} имеет следующие ID поля:\"
    puts \"  id: #{log.id}\"
    puts \"  message_id: #{log.message_id.inspect}\"
    puts \"  postal_message_id: #{log.try(:postal_message_id).inspect}\"
    puts \"  external_message_id: #{log.try(:external_message_id).inspect}\"
    puts ''

    if log.status_details.is_a?(Hash)
      puts 'Webhook передает:'
      puts \"  payload.message.id: #{log.status_details.dig('message', 'id').inspect}\"
      puts \"  payload.message.message_id: #{log.status_details.dig('message', 'message_id').inspect}\"
      puts \"  payload.message.token: #{log.status_details.dig('message', 'token').inspect}\"
    end
  end
"

echo ""
echo "==================================================================="
echo "ПРОВЕРКА ЗАВЕРШЕНА"
echo "==================================================================="
echo ""
