#!/bin/bash
# Deploy SMTP Relay Fix - Complete Flow
set -e

echo "=========================================="
echo "Deploying SMTP Relay Fix"
echo "=========================================="
echo "This will:"
echo "  1. Fix SMTP endpoint URL in relay"
echo "  2. Fix payload format in API controller"
echo "  3. Fix background job processing"
echo "=========================================="
echo ""

# Pull latest changes
echo "→ Pulling latest changes..."
git pull origin claude/setup-email-testing-YifKd

# Rebuild both containers
echo ""
echo "→ Rebuilding smtp-relay container..."
docker compose build smtp-relay

echo ""
echo "→ Rebuilding api container..."
docker compose build api

# Restart containers
echo ""
echo "→ Restarting services..."
docker compose up -d smtp-relay api sidekiq

# Wait for startup
echo ""
echo "→ Waiting for services to start..."
sleep 10

# Check health
echo ""
echo "→ Checking service status..."
docker compose ps | grep -E "(smtp-relay|api|sidekiq)"

echo ""
echo "=========================================="
echo "✓ Deployment complete!"
echo "=========================================="
echo ""
echo "FIXES APPLIED:"
echo "  ✓ SMTP Relay now sends to /api/v1/smtp/receive"
echo "  ✓ API controller accepts correct payload format"
echo "  ✓ Background job processes email data correctly"
echo ""
echo "=========================================="
echo "TEST FROM AMS:"
echo "=========================================="
echo "  Host: linenarrow.com"
echo "  Port: 2587"
echo "  TLS: Yes"
echo "  Auth: Use SMTP credentials from Dashboard"
echo ""
echo "=========================================="
echo "MONITORING LOGS:"
echo "=========================================="
echo "  # SMTP Relay logs:"
echo "  docker compose logs smtp-relay -f"
echo ""
echo "  # API logs (controller + jobs):"
echo "  docker compose logs api -f"
echo ""
echo "  # Sidekiq logs (background processing):"
echo "  docker compose logs sidekiq -f"
echo ""
echo "  # All together:"
echo "  docker compose logs smtp-relay api sidekiq -f"
echo "=========================================="
