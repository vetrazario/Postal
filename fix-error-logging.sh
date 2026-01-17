#!/bin/bash
set -e

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  ИСПРАВЛЕНИЕ ЛОГИРОВАНИЯ ОШИБОК                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

cd /opt/email-sender

echo "1️⃣  Подтягиваю код"
echo "─────────────────────────────────────────────────────────────"
git pull origin claude/project-analysis-errors-Awt4F

echo ""
echo "2️⃣  Проверяю что миграция есть"
echo "─────────────────────────────────────────────────────────────"
if [ -f "services/api/db/migrate/20260117000001_create_delivery_errors.rb" ]; then
  echo "✅ Миграция delivery_errors найдена"
else
  echo "❌ Миграция не найдена!"
  exit 1
fi

echo ""
echo "3️⃣  Применяю миграции"
echo "─────────────────────────────────────────────────────────────"
docker compose exec -T api bundle exec rails db:migrate

echo ""
echo "4️⃣  Проверяю структуру таблицы delivery_errors"
echo "─────────────────────────────────────────────────────────────"
docker compose exec -T postgres psql -U email_sender -d email_sender <<'SQL'
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'delivery_errors'
ORDER BY ordinal_position;
SQL

echo ""
echo "5️⃣  Пересобираю API и Sidekiq"
echo "─────────────────────────────────────────────────────────────"
docker compose build api sidekiq

echo ""
echo "6️⃣  Перезапускаю контейнеры"
echo "─────────────────────────────────────────────────────────────"
docker compose restart api sidekiq

echo ""
echo "⏳ Жду 20 секунд..."
sleep 20

echo ""
echo "7️⃣  Тестирую создание DeliveryError"
echo "─────────────────────────────────────────────────────────────"
docker compose exec -T api bundle exec rails runner '
begin
  # Проверяем модель
  puts "DeliveryError model exists: #{DeliveryError.name}"
  puts "CATEGORIES: #{DeliveryError::CATEGORIES.join(", ")}"
  
  # Проверяем что таблица пустая
  count = DeliveryError.count
  puts "Current records: #{count}"
  
  # Тестовый EmailLog для теста
  email_log = EmailLog.first
  if email_log
    puts "Test EmailLog found: #{email_log.id}"
    
    # Тест создания записи
    test_error = DeliveryError.create!(
      email_log_id: email_log.id,
      campaign_id: email_log.campaign_id,
      category: "connection",
      error_message: "Test error: connection timeout",
      recipient: email_log.recipient
    )
    
    puts "✅ Test DeliveryError created: ID #{test_error.id}"
    
    # Удаляем тестовую запись
    test_error.destroy!
    puts "✅ Test record cleaned up"
  else
    puts "⚠️  No EmailLog found for testing (это нормально если база пустая)"
  end
  
  puts ""
  puts "🎉 МОДЕЛЬ РАБОТАЕТ ПРАВИЛЬНО!"
rescue => e
  puts "❌ ERROR: #{e.class} - #{e.message}"
  puts e.backtrace.first(3).join("\n")
  exit 1
end
'

echo ""
echo "8️⃣  Проверяю что SendSmtpEmailJob использует правильные поля"
echo "─────────────────────────────────────────────────────────────"
if grep -q "email_log_id: email_log.id" services/api/app/jobs/send_smtp_email_job.rb; then
  echo "✅ SendSmtpEmailJob использует правильное поле email_log_id"
else
  echo "❌ SendSmtpEmailJob не исправлен"
  exit 1
fi

if grep -q "category: categorize_error" services/api/app/jobs/send_smtp_email_job.rb; then
  echo "✅ SendSmtpEmailJob использует categorize_error метод"
else
  echo "❌ categorize_error метод не найден"
  exit 1
fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  ✅ ЛОГИРОВАНИЕ ОШИБОК ИСПРАВЛЕНО!                         ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Теперь:"
echo "  1. Отправь тестовую кампанию с неправильным email"
echo "  2. Зайди на /dashboard/error_monitor"
echo "  3. Увидишь ошибки с категориями и деталями!"
echo ""
echo "Категории ошибок:"
echo "  - rate_limit: превышен лимит отправки"
echo "  - spam_block: заблокирован как спам"
echo "  - user_not_found: получатель не найден"
echo "  - mailbox_full: почтовый ящик переполнен"
echo "  - authentication: ошибка аутентификации"
echo "  - connection: проблемы соединения"
echo "  - temporary: временная ошибка"
echo "  - unknown: неизвестная ошибка"
echo ""
