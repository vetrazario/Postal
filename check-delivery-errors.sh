#!/bin/bash
set -e

cd /home/user/Postal

echo "=== Checking DeliveryError Records ==="
echo ""

echo "=== Total DeliveryError records ==="
docker compose exec -T api bundle exec rails runner "
  puts 'Total DeliveryError records: ' + DeliveryError.count.to_s
  puts ''
"

echo "=== Recent DeliveryError records (last 48 hours) ==="
docker compose exec -T api bundle exec rails runner "
  errors = DeliveryError.where('created_at > ?', 48.hours.ago).order(created_at: :desc).limit(20)
  puts \"Found #{errors.count} errors in last 48 hours\"
  puts ''

  if errors.any?
    errors.each do |error|
      log = error.email_log
      puts \"ID: #{error.id}\"
      puts \"  Created: #{error.created_at}\"
      puts \"  Campaign: #{error.campaign_id}\"
      puts \"  Category: #{error.category}\"
      puts \"  SMTP Code: #{error.smtp_code || 'N/A'}\"
      puts \"  SMTP Message: #{error.smtp_message&.truncate(100) || 'N/A'}\"
      puts \"  Recipient Domain: #{error.recipient_domain || 'N/A'}\"
      puts \"  EmailLog ID: #{error.email_log_id}, Status: #{log&.status || 'N/A'}, Recipient: #{log&.recipient || 'N/A'}\"
      puts ''
    end
  else
    puts 'No errors found in last 48 hours'
  end
"

echo "=== DeliveryError by Category (last 24h) ==="
docker compose exec -T api bundle exec rails runner "
  stats = DeliveryError.where('created_at > ?', 24.hours.ago).group(:category).count
  puts 'Category breakdown:'
  stats.each do |category, count|
    puts \"  #{category}: #{count}\"
  end
  puts '  TOTAL: ' + stats.values.sum.to_s
"

echo ""
echo "=== Failed EmailLog records WITHOUT DeliveryError (last 24h) ==="
docker compose exec -T api bundle exec rails runner "
  failed_logs = EmailLog.where(status: 'failed', created_at: 24.hours.ago..Time.current)
  puts \"Total failed EmailLog records: #{failed_logs.count}\"

  # Find failed logs without DeliveryError
  failed_without_error = failed_logs.select { |log| log.campaign_id.present? && DeliveryError.where(email_log_id: log.id).count == 0 }
  puts \"Failed logs WITHOUT DeliveryError: #{failed_without_error.count}\"
  puts ''

  if failed_without_error.any?
    puts 'First 10 failed logs without DeliveryError:'
    failed_without_error.first(10).each do |log|
      puts \"  EmailLog ID: #{log.id}, Campaign: #{log.campaign_id}, Status: #{log.status}, Created: #{log.created_at}\"
      puts \"  Recipient: #{log.recipient}\"
      puts \"  Details: #{log.details.inspect}\"
      puts ''
    end
  end
"

echo ""
echo "=== Checking if SendSmtpEmailJob creates DeliveryError ==="
docker compose logs --tail=200 sidekiq | grep -E "DeliveryError|SendSmtpEmailJob.*error|SendSmtpEmailJob.*failed" | tail -n 20 || echo "No error logs found in Sidekiq"

echo ""
echo "=== Checking if webhooks create DeliveryError ==="
docker compose logs --tail=200 api | grep -E "DeliveryError|MessageHeld|MessageBounced" | tail -n 20 || echo "No webhook logs found in API"

echo ""
echo "=== ✅ Done ==="
