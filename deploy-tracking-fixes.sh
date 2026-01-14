#!/bin/bash
# Deploy tracking and campaign_id fixes
# This script rebuilds and restarts API and Sidekiq with the latest code changes

set -e

echo "=================================================="
echo "🚀 Deploying Tracking & Campaign Fixes"
echo "=================================================="
echo ""

echo "📝 Changes being deployed:"
echo "  ✓ Fixed ErrorClassifier constant error (auto-stop)"
echo "  ✓ Enabled click tracking in Postal"
echo "  ✓ Enabled open tracking in Postal"
echo "  ✓ Pass campaign_id for proper context"
echo ""

echo "🔨 Step 1: Rebuilding API and Sidekiq images..."
docker compose build api sidekiq
echo "✅ Images rebuilt"
echo ""

echo "🔄 Step 2: Restarting API and Sidekiq services..."
docker compose up -d --force-recreate --no-deps api sidekiq
echo "✅ Services restarted"
echo ""

echo "⏳ Step 3: Waiting for services to be healthy..."
sleep 10

echo "🔍 Step 4: Verifying deployment..."
echo ""

echo "--- Service Status ---"
docker compose ps api sidekiq
echo ""

echo "--- API Health Check ---"
curl -s http://localhost/api/v1/health | jq . 2>/dev/null || echo "API is starting up..."
echo ""

echo "--- Sidekiq Status ---"
docker compose exec -T api rails runner "stats = Sidekiq::Stats.new; puts \"Processed: #{stats.processed}, Failed: #{stats.failed}, Queues: #{Sidekiq::Queue.all.map(&:name).join(', ')}\"" 2>/dev/null || echo "Sidekiq is starting up..."
echo ""

echo "--- Recent Logs (API) ---"
docker compose logs --tail=20 api
echo ""

echo "=================================================="
echo "✅ Deployment Complete!"
echo "=================================================="
echo ""
echo "Next steps:"
echo "1. Test by sending a new campaign from AMS"
echo "2. Check that links are replaced with tracking URLs"
echo "3. Verify unsubscribe link appears in email headers"
echo "4. Confirm opens and clicks are tracked"
echo "5. Test auto-stop with a bounce"
echo ""
echo "To monitor logs:"
echo "  docker compose logs -f api sidekiq"
echo ""
