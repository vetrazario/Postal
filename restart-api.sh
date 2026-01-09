#!/bin/bash
# Restart API container with new environment variable

echo "🔄 Restarting API container..."
docker compose up -d --force-recreate --no-deps api

echo "⏳ Waiting for API to be healthy..."
sleep 5

echo "✅ Checking API status..."
docker compose ps api

echo ""
echo "📋 Checking if webhook verification is disabled..."
docker compose exec -T api printenv | grep SKIP_POSTAL_WEBHOOK_VERIFICATION || echo "❌ Variable not found"

echo ""
echo "✅ Done! Now webhook verification should be skipped."
echo ""
echo "To test, send an email via API and check webhook logs:"
echo "  docker compose exec -T postgres psql -U email_sender -d email_sender -c \"SELECT event_type, success, response_status, created_at FROM webhook_logs ORDER BY created_at DESC LIMIT 3;\""
