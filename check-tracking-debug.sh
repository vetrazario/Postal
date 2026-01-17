#!/bin/bash
set -e

cd /home/user/Postal

echo "=== Checking Tracking Debug Logs ==="
echo ""
echo "This will show the last 200 lines of logs containing [LinkTracker] or [SendSmtpEmailJob]"
echo ""

echo "=== Sidekiq Logs (where tracking happens) ==="
docker compose logs --tail=500 sidekiq | grep -E "\[LinkTracker\]|\[SendSmtpEmailJob\]" | tail -n 100 || echo "No tracking logs found yet"

echo ""
echo "=== API Logs ==="
docker compose logs --tail=500 api | grep -E "\[LinkTracker\]|\[SendSmtpEmailJob\]" | tail -n 100 || echo "No tracking logs found yet"

echo ""
echo "=== What to look for ==="
echo "1. [LinkTracker] Starting track_links - confirms tracking is called"
echo "2. [LinkTracker] Found X links in HTML - shows link detection"
echo "3. [LinkTracker] Replaced link - shows each replacement"
echo "4. [SendSmtpEmailJob] HTML changed: true - confirms modification"
echo ""
echo "=== Recent EmailClick records ==="
docker compose exec -T api bundle exec rails runner "
  puts 'Recent EmailClick records:'
  EmailClick.order(created_at: :desc).limit(5).each do |click|
    puts \"- ID: #{click.id}, Token: #{click.token[0..15]}, URL: #{click.url[0..60]}, Clicked: #{click.clicked_at.present?}\"
  end
"

echo ""
echo "=== Dashboard Overview Stats ==="
docker compose exec -T api bundle exec rails runner "
  logs = EmailLog.where(created_at: 1.day.ago..Time.current)
  clicks = EmailClick.where(email_log_id: logs.ids).where.not(clicked_at: nil).count
  opens = EmailOpen.where(email_log_id: logs.ids).where.not(opened_at: nil).count
  puts \"Last 24h: Emails=#{logs.count}, Opens=#{opens}, Clicks=#{clicks}\"
"

echo ""
echo "=== ✅ Done ==="
