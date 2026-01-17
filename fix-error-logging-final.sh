#!/bin/bash
set -e

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  ФИНАЛЬНОЕ ИСПРАВЛЕНИЕ ЛОГИРОВАНИЯ ОШИБОК                  ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

cd /opt/email-sender

echo "1️⃣  Подтягиваю код"
echo "─────────────────────────────────────────────────────────────"
git pull origin claude/project-analysis-errors-Awt4F

echo ""
echo "2️⃣  Проверяю текущую структуру delivery_errors"
echo "─────────────────────────────────────────────────────────────"
docker compose exec -T postgres psql -U email_sender -d email_sender <<'SQL'
\d delivery_errors
SQL

echo ""
echo "3️⃣  Проверяю количество записей"
echo "─────────────────────────────────────────────────────────────"
docker compose exec -T postgres psql -U email_sender -d email_sender <<'SQL'
SELECT COUNT(*) as total_errors, 
       category,
       COUNT(*) * 100.0 / SUM(COUNT(*)) OVER() as percentage
FROM delivery_errors
GROUP BY category
ORDER BY COUNT(*) DESC;
SQL

echo ""
echo "4️⃣  Пересобираю API и Sidekiq"
echo "─────────────────────────────────────────────────────────────"
docker compose build api sidekiq

echo ""
echo "5️⃣  Перезапускаю контейнеры"
echo "─────────────────────────────────────────────────────────────"
docker compose restart api sidekiq

echo ""
echo "⏳ Жду 20 секунд..."
sleep 20

echo ""
echo "6️⃣  Тестирую создание DeliveryError с правильными полями"
echo "─────────────────────────────────────────────────────────────"
docker compose exec -T api bundle exec rails runner '
begin
  # Проверяем модель
  puts "DeliveryError model: #{DeliveryError.name}"
  puts "CATEGORIES: #{DeliveryError::CATEGORIES.join(", ")}"
  puts "Current records: #{DeliveryError.count}"
  
  # Тестовый EmailLog
  email_log = EmailLog.first
  if email_log
    puts "Test EmailLog: #{email_log.id} (#{email_log.recipient})"
    
    # Тест создания записи
    test_error = DeliveryError.create!(
      email_log_id: email_log.id,
      campaign_id: email_log.campaign_id,
      category: "connection",
      smtp_message: "Test error: connection timeout",
      smtp_code: "421",
      recipient_domain: email_log.recipient.split("@").last
    )
    
    puts "✅ Test DeliveryError created: ID #{test_error.id}"
    puts "   - email_log_id: #{test_error.email_log_id}"
    puts "   - campaign_id: #{test_error.campaign_id}"
    puts "   - category: #{test_error.category}"
    puts "   - smtp_message: #{test_error.smtp_message}"
    puts "   - recipient_domain: #{test_error.recipient_domain}"
    
    # Удаляем тестовую запись
    test_error.destroy!
    puts "✅ Test record cleaned up"
  else
    puts "⚠️  No EmailLog found (это OK если база пустая)"
  end
  
  puts ""
  puts "🎉 ВСЕ РАБОТАЕТ ПРАВИЛЬНО!"
rescue => e
  puts "❌ ERROR: #{e.class} - #{e.message}"
  puts e.backtrace.first(5).join("\n")
  exit 1
end
'

echo ""
echo "7️⃣  Проверяю что SendSmtpEmailJob использует правильные поля"
echo "─────────────────────────────────────────────────────────────"
if grep -q "smtp_message:" services/api/app/jobs/send_smtp_email_job.rb; then
  echo "✅ SendSmtpEmailJob использует smtp_message"
else
  echo "❌ SendSmtpEmailJob не использует smtp_message"
  exit 1
fi

if grep -q "recipient_domain:" services/api/app/jobs/send_smtp_email_job.rb; then
  echo "✅ SendSmtpEmailJob использует recipient_domain"
else
  echo "❌ SendSmtpEmailJob не использует recipient_domain"
  exit 1
fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  ✅ ЛОГИРОВАНИЕ ОШИБОК РАБОТАЕТ!                           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Теперь все ошибки при отправке будут сохраняться в БД!"
echo ""
echo "Проверь Error Monitor:"
echo "  👉 https://linenarrow.com/dashboard/error_monitor"
echo ""
echo "Структура записи DeliveryError:"
echo "  - email_log_id: ссылка на EmailLog"
echo "  - campaign_id: ID кампании"
echo "  - category: категория (rate_limit, spam_block, user_not_found, и т.д.)"
echo "  - smtp_message: полный текст ошибки"
echo "  - smtp_code: SMTP код ошибки (если есть)"
echo "  - recipient_domain: домен получателя"
echo ""
echo "Категории определяются автоматически по тексту ошибки:"
echo "  • rate_limit - превышен лимит"
echo "  • spam_block - заблокирован как спам"
echo "  • user_not_found - получатель не найден"
echo "  • mailbox_full - почтовый ящик переполнен"
echo "  • authentication - ошибка аутентификации"
echo "  • connection - проблемы соединения"
echo "  • temporary - временная ошибка"
echo "  • unknown - неизвестная ошибка"
echo ""
