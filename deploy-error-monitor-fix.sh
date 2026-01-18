#!/bin/bash
set -e

cd /opt/email-sender

echo "=================================================================="
echo "DEPLOYING ERROR MONITOR FIX"
echo "=================================================================="
echo ""

echo "=== 1. Pulling latest changes ==="
git pull origin claude/project-analysis-errors-Awt4F

echo ""
echo "=== 2. Stopping API container ==="
docker compose stop api

echo ""
echo "=== 3. Removing API container ==="
docker compose rm -f api

echo ""
echo "=== 4. Rebuilding API container (no cache) ==="
docker compose build --no-cache api

echo ""
echo "=== 5. Starting API container ==="
docker compose up -d

echo ""
echo "=== 6. Waiting for API to start (10 seconds) ==="
sleep 10

echo ""
echo "=== 7. Verifying fix is deployed ==="
docker compose exec -T api bundle exec rails runner "
  code = File.read('app/models/bounced_email.rb')

  if code.include?('ErrorClassifier.should_add_to_bounce?')
    puts '✅ FIX DEPLOYED: Using method ErrorClassifier.should_add_to_bounce?'
  else
    puts '❌ OLD CODE: Still using NON_BOUNCE_CATEGORIES constant'
  end
"

echo ""
echo "=================================================================="
echo "DEPLOYMENT COMPLETE"
echo "=================================================================="
echo ""
echo "Next step: Run test-error-monitor-after-fix.sh to verify"
echo ""
