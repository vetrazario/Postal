#!/bin/bash
set -e

cd /opt/email-sender

echo "=================================================================="
echo "TESTING ERROR MONITOR AFTER FIX"
echo "=================================================================="
echo ""

echo "=== 1. Sending test email to non-existent address ==="
docker compose exec -T api bundle exec rails runner "
campaign_id = EmailLog.where.not(campaign_id: nil).order(created_at: :desc).first&.campaign_id || 'test-999'

puts \"Using campaign_id: #{campaign_id}\"
puts ''

# Create EmailLog
log = EmailLog.create!(
  message_id: 'test-fix-' + SecureRandom.hex(8),
  recipient: 'nonexistent-user-999999@gmail.com',
  sender: 'info@linenarrow.com',
  subject: 'Test Error Monitor Fix',
  status: 'queued',
  campaign_id: campaign_id.to_s,
  external_message_id: '<test-fix-' + SecureRandom.hex(8) + '@linenarrow.com>'
)

puts \"✅ EmailLog created: ##{log.id}\"
puts \"   Campaign: #{log.campaign_id}\"
puts \"   Recipient: #{log.recipient}\"
puts ''

# Queue job
email_data = {
  email_log_id: log.id,
  envelope: {
    from: 'info@linenarrow.com',
    to: 'nonexistent-user-999999@gmail.com'
  },
  message: {
    subject: 'Test Error Monitor Fix',
    text: 'Testing DeliveryError creation after fix.',
    html: '<p>Testing DeliveryError creation after fix.</p>'
  }
}

SendSmtpEmailJob.perform_later(email_data)
puts '✅ Job queued'
"

echo ""
echo "Waiting 60 seconds for webhook processing..."
for i in {60..1}; do
  printf "Remaining: %2d seconds...\r" $i
  sleep 1
done
echo ""
echo ""

echo "=== 2. Checking production.log for errors ==="
docker compose exec -T api tail -n 100 /app/log/production.log | grep -i "webhook error\|NON_BOUNCE_CATEGORIES\|test-fix" || echo "  (no errors found - good!)"

echo ""
echo "=== 3. Checking if DeliveryError was created ==="
docker compose exec -T api bundle exec rails runner "
  recent = DeliveryError.where('created_at > ?', 2.minutes.ago).order(created_at: :desc)

  puts \"DeliveryError created in last 2 minutes: #{recent.count}\"
  puts ''

  if recent.any?
    puts '✅ SUCCESS! DeliveryError records created:'
    recent.each do |err|
      log = err.email_log
      puts \"  ##{err.id}:\"
      puts \"    Campaign: #{err.campaign_id}\"
      puts \"    Category: #{err.category}\"
      puts \"    Recipient: #{log&.recipient_masked}\"
      puts \"    Created: #{err.created_at}\"
      puts ''
    end

    puts '✅ ERROR MONITOR FIX WORKING!'
  else
    puts '❌ No DeliveryError created - check logs above for issues'
  end
"

echo ""
echo "=== 4. Checking Error Monitor UI ==="
echo "Visit: https://linenarrow.com/dashboard/error_monitor"
echo ""

echo "=================================================================="
echo "TEST COMPLETE"
echo "=================================================================="
echo ""
