#!/bin/bash
set -e

cd /opt/email-sender

echo "==================================================================="
echo "ПРОВЕРКА КОНФИГУРАЦИИ POSTAL WEBHOOKS"
echo "==================================================================="
echo ""

echo "=== 1. Как отправляются emails? ==="
docker compose exec -T api bundle exec rails runner "
  code = File.read('app/jobs/send_smtp_email_job.rb')

  if code.include?('PostalClient')
    puts '✅ Используется PostalClient (Postal API)'
    puts ''
    puts 'Postal API URL:'
    puts ENV.fetch('POSTAL_API_URL', 'не задан')
    puts ''
    puts 'Postal API KEY:'
    puts ENV.fetch('POSTAL_API_KEY', 'не задан') ? '✅ задан' : '❌ не задан'
  else
    puts 'Используется прямая SMTP отправка (без Postal)'
  end
"

echo ""
echo "=== 2. Проверка PostalClient ==="
docker compose exec -T api bundle exec rails runner "
  if defined?(PostalClient)
    puts '✅ PostalClient класс существует'
    puts ''
    puts 'Проверка методов...'
    puts PostalClient.instance_methods(false).inspect
  else
    puts '❌ PostalClient класс НЕ найден'
  end
"

echo ""
echo "=== 3. Проверка ENV переменных Postal ==="
docker compose exec -T api printenv | grep -i postal || echo "  (нет POSTAL_* переменных)"

echo ""
echo "=== 4. Проверка конфигурации webhook в Postal ==="
echo "Postal должен быть настроен для отправки webhook'ов на:"
echo "  https://linenarrow.com/api/v1/webhooks/postal"
echo ""
echo "Проверим настройки Postal через API..."

docker compose exec -T api bundle exec rails runner "
  api_url = ENV.fetch('POSTAL_API_URL', 'http://postal:5000')
  api_key = ENV.fetch('POSTAL_API_KEY', '')

  puts \"Postal API URL: #{api_url}\"
  puts \"Postal API KEY: #{api_key.present? ? '✅ задан' : '❌ не задан'}\"
  puts ''

  if api_url.present? && api_key.present?
    puts 'Попытка подключения к Postal API...'
    # Проверка доступности Postal
    begin
      require 'net/http'
      uri = URI(api_url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 5, read_timeout: 5) do |http|
        http.get('/')
      end
      puts \"✅ Postal доступен (HTTP #{response.code})\"
    rescue => e
      puts \"❌ Postal недоступен: #{e.message}\"
    end
  else
    puts '❌ Postal API не настроен (нет URL или KEY)'
  end
"

echo ""
echo "=== 5. Проверка webhook в status_details ==="
docker compose exec -T api bundle exec rails runner "
  failed = EmailLog.where(status: 'failed').order(created_at: :desc).first

  if failed
    puts 'Последний failed EmailLog:'
    puts \"  ID: #{failed.id}\"
    puts \"  Status: #{failed.status}\"
    puts ''

    details = failed.status_details || {}
    puts 'Status Details (откуда пришло):'
    puts \"  Тип данных: #{details.class}\"
    puts \"  Ключи: #{details.keys.inspect}\"
    puts ''
    puts 'Полное содержимое:'
    puts details.inspect
  else
    puts 'Нет failed EmailLog'
  end
"

echo ""
echo "=== 6. Как EmailLog получает status='failed'? ==="
docker compose exec -T api bundle exec rails runner "
  code = File.read('app/models/email_log.rb')

  if code.include?('update_status')
    puts '✅ EmailLog имеет метод update_status'

    # Найти метод
    method_code = code.match(/def update_status.*?end/m)
    if method_code
      puts ''
      puts 'Метод update_status:'
      puts method_code[0]
    end
  else
    puts 'EmailLog использует update! напрямую'
  end
"

echo ""
echo "==================================================================="
echo "ПРОВЕРКА ЗАВЕРШЕНА"
echo "==================================================================="
echo ""
echo "ВЫВОДЫ:"
echo "-------"
echo "Если webhook'и НЕ приходят, возможные причины:"
echo ""
echo "1. Postal не настроен для отправки webhook'ов"
echo "   → Нужно настроить webhook endpoint в Postal UI"
echo ""
echo "2. Emails отправляются через SMTP, а не через Postal API"
echo "   → Postal не знает о нашем API и не шлет webhook'и"
echo ""
echo "3. Webhook URL неправильный в Postal"
echo "   → Должен быть: https://linenarrow.com/api/v1/webhooks/postal"
echo ""
echo "4. Status='failed' устанавливается НЕ через webhook"
echo "   → Устанавливается в другом месте (SendSmtpEmailJob?)"
echo ""
