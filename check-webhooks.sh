#!/bin/bash
set -e

cd /opt/email-sender

echo "==================================================================="
echo "ПРОВЕРКА WEBHOOKS ОБРАБОТКИ"
echo "==================================================================="
echo ""

echo "=== 1. Проверка логов API для webhooks ==="
echo "Ищем MessageHeld и MessageDeliveryFailed в логах..."
docker compose logs --tail=2000 api | grep -E "MessageHeld|MessageDeliveryFailed|MessageBounced|webhook" | tail -n 50 || echo "  (нет webhook логов)"

echo ""
echo "=== 2. Проверка последних запросов к /api/v1/webhooks ==="
docker compose logs --tail=1000 api | grep -i "POST.*webhook" | tail -n 20 || echo "  (нет POST запросов к webhooks)"

echo ""
echo "=== 3. Проверка EmailLog update_status вызовов ==="
docker compose logs --tail=1000 api | grep -i "update_status\|EmailLog.*failed\|EmailLog.*status" | tail -n 30 || echo "  (нет логов update_status)"

echo ""
echo "=== 4. Проверка наличия WebhooksController логов ==="
docker compose logs --tail=1000 api | grep -i "WebhooksController" | tail -n 30 || echo "  (нет логов WebhooksController)"

echo ""
echo "=== 5. Проверка ошибок в API ==="
docker compose logs --tail=1000 api | grep -iE "error|exception|failed" | grep -v "HardFail\|\"failed\"" | tail -n 30 || echo "  (нет ошибок в логах)"

echo ""
echo "=== 6. Включить дебаг-логирование в webhooks_controller ==="
echo "Проверим, вызывается ли вообще webhooks_controller..."
docker compose exec -T api bundle exec rails runner "
  puts 'Checking webhooks_controller code...'
  code = File.read('app/controllers/api/v1/webhooks_controller.rb')

  if code.include?('Rails.logger.info')
    puts '✅ В webhooks_controller уже есть логирование'
  else
    puts '⚠️ В webhooks_controller НЕТ достаточного логирования'
  end

  # Проверить, есть ли логи создания DeliveryError
  if code.include?('[WebhooksController] DeliveryError created')
    puts '✅ Есть логи создания DeliveryError'
  else
    puts '⚠️ НЕТ логов создания DeliveryError'
  end
"

echo ""
echo "=== 7. Проверка конфигурации Postal webhook URL ==="
echo "Куда Postal отправляет webhooks?"
docker compose exec -T api bundle exec rails runner "
  puts 'Expected webhook URL:'
  puts \"  http://api:3000/api/v1/webhooks (from Postal container)\"
  puts \"  or\"
  puts \"  https://linenarrow.com/api/v1/webhooks (if Postal sends externally)\"
  puts ''

  # Проверить env
  webhook_url = ENV['POSTAL_WEBHOOK_URL']
  puts \"POSTAL_WEBHOOK_URL env: #{webhook_url.inspect}\"
"

echo ""
echo "=== 8. Вручную триггернуть webhook для failed EmailLog ==="
echo "Симулируем MessageHeld webhook..."
docker compose exec -T api bundle exec rails runner "
  require 'net/http'
  require 'json'

  # Найти failed EmailLog
  log = EmailLog.where(status: 'failed').order(created_at: :desc).first

  if log.nil?
    puts '❌ Нет failed EmailLog для теста'
  else
    puts \"Используем EmailLog ##{log.id}\"
    puts \"  Message ID: #{log.message_id}\"
    puts \"  Campaign: #{log.campaign_id}\"
    puts ''

    # Создать webhook payload (как Postal отправляет)
    payload = {
      event: 'MessageHeld',
      uuid: SecureRandom.uuid,
      timestamp: Time.current.to_f,
      payload: {
        message: {
          id: 999,
          token: 'test-token',
          direction: 'outgoing'
        },
        original_message: {
          message_id: log.message_id
        },
        status: 'Held',
        details: 'TEST: Simulated webhook for diagnostic',
        output: '',
        time: nil,
        timestamp: Time.current.to_f
      }
    }

    puts 'Отправляем POST /api/v1/webhooks...'
    puts ''

    begin
      uri = URI('http://localhost:3000/api/v1/webhooks')
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
      req.body = payload.to_json

      response = http.request(req)
      puts \"Response: #{response.code} #{response.message}\"
      puts \"Body: #{response.body}\"

      # Проверить, создался ли DeliveryError
      sleep 1
      delivery_error = DeliveryError.where(email_log_id: log.id).last
      if delivery_error
        puts ''
        puts \"✅ DeliveryError создан: ##{delivery_error.id}\"
      else
        puts ''
        puts '❌ DeliveryError НЕ создан после webhook!'
      end
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
