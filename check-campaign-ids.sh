#!/bin/bash
set -e

cd /home/user/Postal

echo "=== Checking EmailLog campaign_id Status ==="
echo ""

echo "=== Failed EmailLog records (last 48h) ==="
docker compose exec -T api bundle exec rails runner "
  failed = EmailLog.where(status: 'failed', created_at: 48.hours.ago..Time.current)
  puts \"Total failed EmailLog: #{failed.count}\"

  with_campaign = failed.where.not(campaign_id: nil).count
  without_campaign = failed.where(campaign_id: nil).count

  puts \"  With campaign_id: #{with_campaign}\"
  puts \"  WITHOUT campaign_id: #{without_campaign}\"
  puts ''

  if without_campaign > 0
    puts 'First 10 failed logs WITHOUT campaign_id:'
    failed.where(campaign_id: nil).limit(10).each do |log|
      puts \"  ID: #{log.id}, Recipient: #{log.recipient_masked}, Status: #{log.status}, Created: #{log.created_at}\"
    end
    puts ''
  end
"

echo "=== Bounced EmailLog records (last 48h) ==="
docker compose exec -T api bundle exec rails runner "
  bounced = EmailLog.where(status: 'bounced', created_at: 48.hours.ago..Time.current)
  puts \"Total bounced EmailLog: #{bounced.count}\"

  with_campaign = bounced.where.not(campaign_id: nil).count
  without_campaign = bounced.where(campaign_id: nil).count

  puts \"  With campaign_id: #{with_campaign}\"
  puts \"  WITHOUT campaign_id: #{without_campaign}\"
"

echo ""
echo "=== DeliveryError records (last 48h) ==="
docker compose exec -T api bundle exec rails runner "
  errors = DeliveryError.where(created_at: 48.hours.ago..Time.current)
  puts \"Total DeliveryError: #{errors.count}\"
  puts ''

  if errors.any?
    puts 'Recent DeliveryError records:'
    errors.order(created_at: :desc).limit(10).each do |error|
      puts \"  ID: #{error.id}, Campaign: #{error.campaign_id}, Category: #{error.category}, Created: #{error.created_at}\"
    end
  end
"

echo ""
echo "=== Checking logs for DeliveryError creation ==="
echo "Looking for [SendSmtpEmailJob] and [WebhooksController] DeliveryError logs..."
docker compose logs --tail=500 sidekiq api | grep -E "DeliveryError (created|NOT created)" | tail -n 20 || echo "No DeliveryError creation logs found"

echo ""
echo "=== ✅ Done ==="
echo ""
echo "If you see 'WITHOUT campaign_id' > 0, that's why errors don't appear in Error Monitor!"
echo "Error Monitor REQUIRES campaign_id to be present."
echo ""
