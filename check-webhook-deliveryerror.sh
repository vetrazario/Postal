#!/bin/bash
set -e

cd /opt/email-sender

echo "==================================================================="
echo "ПРОВЕРКА WEBHOOKS СОЗДАНИЯ DELIVERYERROR"
echo "==================================================================="
echo ""

echo "=== 1. Проверка webhooks_controller.rb - где создается DeliveryError ==="
docker compose exec -T api bundle exec rails runner "
  code = File.read('app/controllers/api/v1/webhooks_controller.rb')

  puts 'Ищем все места создания DeliveryError...'
  puts ''

  lines = code.lines
  lines.each_with_index do |line, idx|
    if line.include?('DeliveryError.create')
      puts \"Строка #{idx + 1}: #{line.strip}\"

      # Показать контекст (10 строк до)
      puts '  Контекст (10 строк до):'
      (idx - 10..idx - 1).each do |i|
        next if i < 0
        puts \"    #{i + 1}: #{lines[i].strip}\"
      end
      puts ''
    end
  end
"

echo ""
echo "=== 2. Проверка какие webhook события приходят для failed EmailLog ==="
docker compose exec -T api bundle exec rails runner "
  failed = EmailLog.where(status: 'failed', created_at: 7.days.ago..Time.current)
                    .order(created_at: :desc)
                    .limit(5)

  puts 'Проверка webhook событий в status_details:'
  puts ''

  failed.each do |log|
    details = log.status_details || {}
    webhook_status = details['status'] || details[:status]

    puts \"EmailLog ##{log.id}:\"
    puts \"  Webhook Status: #{webhook_status.inspect}\"
    puts \"  Details: #{(details['details'] || details[:details]).to_s[0..100]}\"
    puts ''
  end
"

echo ""
echo "=== 3. Проверка логов webhook обработки ==="
echo "Ищем MessageHeld в логах API..."
docker compose logs --tail=1000 api | grep -i "MessageHeld" | tail -n 20 || echo "  (не найдено)"

echo ""
echo "Ищем MessageBounced в логах API..."
docker compose logs --tail=1000 api | grep -i "MessageBounced\|MessageDeliveryFailed" | tail -n 20 || echo "  (не найдено)"

echo ""
echo "Ищем DeliveryError в логах API (webhooks)..."
docker compose logs --tail=1000 api | grep -i "DeliveryError" | tail -n 20 || echo "  (не найдено)"

echo ""
echo "=== 4. Добавление DEBUG логирования в webhooks_controller ==="
echo "Сейчас добавлю временное логирование для отладки..."

docker compose exec -T api bundle exec rails runner "
  # Проверим, получает ли webhooks_controller вообще события
  puts 'Проверка последних webhook событий (если логируются)...'

  # Попробуем найти в логах
  puts 'Проверьте логи API командой:'
  puts '  docker compose logs -f api | grep -i webhook'
"

echo ""
echo "=== 5. Проверка - обрабатывается ли MessageHeld правильно ==="
docker compose exec -T api bundle exec rails runner "
  code = File.read('app/controllers/api/v1/webhooks_controller.rb')

  # Найти блок when 'MessageHeld'
  if code.include?(\"when 'MessageHeld'\")
    puts \"✅ Обработчик 'MessageHeld' найден\"

    # Проверить, создается ли DeliveryError
    held_section = code.match(/when 'MessageHeld'.*?(?=when '|end\s*$)/m)
    if held_section
      held_code = held_section[0]

      if held_code.include?('DeliveryError.create')
        puts \"✅ В обработчике MessageHeld есть DeliveryError.create!\"

        if held_code.include?('if email_log.campaign_id.present?')
          puts \"✅ Есть проверка campaign_id.present?\"
        else
          puts \"❌ НЕТ проверки campaign_id.present?\"
        end

        # Показать код создания
        puts ''
        puts 'Код создания DeliveryError в MessageHeld:'
        held_code.lines.each do |line|
          if line.include?('DeliveryError') || line.include?('campaign_id') || line.include?('category')
            puts \"  #{line}\"
          end
        end
      else
        puts \"❌ В обработчике MessageHeld НЕТ DeliveryError.create!\"
      end
    end
  else
    puts \"❌ Обработчик 'MessageHeld' НЕ найден\"
  end
"

echo ""
echo "==================================================================="
echo "ПРОВЕРКА ЗАВЕРШЕНА"
echo "==================================================================="
echo ""
