#!/bin/bash
# Verify that tracking fixes are deployed and working
# Run this AFTER deploy-tracking-fixes.sh

set -e

echo "=================================================="
echo "🔍 Verifying Tracking & Campaign Fixes"
echo "=================================================="
echo ""

echo "1️⃣ Checking ErrorClassifier has stop_mailing_categories method..."
docker compose exec -T api rails runner "
begin
  categories = ErrorClassifier.stop_mailing_categories
  puts '✅ ErrorClassifier.stop_mailing_categories works'
  puts \"   Categories: #{categories.join(', ')}\"
rescue => e
  puts '❌ ERROR: ' + e.message
  exit 1
end
"
echo ""

echo "2️⃣ Checking PostalClient sends track_clicks and track_opens..."
docker compose exec -T api rails runner "
code = File.read('app/services/postal_client.rb')
if code.include?('track_clicks: true') && code.include?('track_opens: true')
  puts '✅ PostalClient has tracking flags enabled'
else
  puts '❌ ERROR: PostalClient missing tracking flags'
  exit 1
end
"
echo ""

echo "3️⃣ Checking SendSmtpEmailJob passes campaign_id..."
docker compose exec -T api rails runner "
code = File.read('app/jobs/send_smtp_email_job.rb')
if code.include?('campaign_id: email_log.campaign_id')
  puts '✅ SendSmtpEmailJob passes campaign_id to PostalClient'
else
  puts '❌ ERROR: SendSmtpEmailJob not passing campaign_id'
  exit 1
end
"
echo ""

echo "4️⃣ Checking recent EmailLog records..."
docker compose exec -T api rails runner "
recent = EmailLog.order(created_at: :desc).limit(5)
puts '--- Recent Emails ---'
recent.each do |log|
  puts \"ID: #{log.id} | Campaign: #{log.campaign_id || 'NONE'} | Status: #{log.status} | Recipient: #{log.recipient_masked}\"
end
"
echo ""

echo "5️⃣ Checking CampaignStats..."
docker compose exec -T api rails runner "
stats = CampaignStats.order(updated_at: :desc).limit(3)
if stats.any?
  puts '--- Campaign Statistics ---'
  stats.each do |s|
    puts \"Campaign #{s.campaign_id}: Sent: #{s.total_sent}, Delivered: #{s.total_delivered}, Bounced: #{s.total_bounced}\"
  end
else
  puts 'No campaign stats yet'
end
"
echo ""

echo "6️⃣ Checking bounce patterns configuration..."
docker compose exec -T api rails runner "
config_path = Rails.root.join('config', 'bounce_patterns.yml')
if File.exist?(config_path)
  puts '✅ Bounce patterns YAML exists'
  config = YAML.safe_load(File.read(config_path))
  pattern_count = config['patterns']&.size || 0
  stop_count = config['stop_mailing_categories']&.size || 0
  puts \"   Patterns: #{pattern_count}, Stop categories: #{stop_count}\"
else
  puts '⚠️  Bounce patterns YAML not found, using defaults'
end
"
echo ""

echo "=================================================="
echo "✅ Verification Complete!"
echo "=================================================="
echo ""
echo "If all checks passed, send a test campaign and verify:"
echo "1. In received email: Check if links are tracking URLs"
echo "2. In email headers: Look for List-Unsubscribe with your domain"
echo "3. Dashboard: Check if opens/clicks are recorded"
echo "4. Error Monitor: Send to fake address and verify bounce is classified"
echo ""
