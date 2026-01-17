#!/bin/bash
set -e

echo "=== Fixing Tracking Issues ==="
echo ""
echo "Changes:"
echo "1. ✅ Dashboard overview now uses EmailClick/EmailOpen instead of TrackingEvent"
echo "2. ✅ Added debug logging to LinkTracker.track_links()"
echo "3. ✅ Added debug logging to SendSmtpEmailJob"
echo ""

cd /home/user/Postal

echo "=== Stopping API service ==="
docker compose stop api

echo "=== Removing API container ==="
docker compose rm -f api

echo "=== Rebuilding API with no cache ==="
docker compose build --no-cache api

echo "=== Starting services ==="
docker compose up -d

echo "=== Waiting for services to be ready ==="
sleep 10

echo "=== Checking Sidekiq ==="
docker compose exec -T api bundle exec rails runner "puts 'Sidekiq processes: ' + Sidekiq::ProcessSet.new.size.to_s"

echo ""
echo "=== ✅ Done! ==="
echo ""
echo "Now you can:"
echo "1. Send a test email with a link"
echo "2. Check logs: docker compose logs -f --tail=100 api sidekiq"
echo "3. Look for [LinkTracker] and [SendSmtpEmailJob] log entries"
echo ""
echo "Expected behavior:"
echo "- Dashboard overview should show clicks correctly"
echo "- Logs will show if HTML is being modified"
echo ""
