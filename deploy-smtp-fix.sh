#!/bin/bash
# Deploy SMTP Relay endpoint fix
set -e

echo "=========================================="
echo "Deploying SMTP Relay Fix"
echo "=========================================="

# Pull latest changes
echo "→ Pulling latest changes..."
git pull origin claude/setup-email-testing-YifKd

# Rebuild SMTP relay container
echo "→ Rebuilding smtp-relay container..."
docker compose build smtp-relay

# Restart container
echo "→ Restarting smtp-relay..."
docker compose up -d smtp-relay

# Wait for startup
echo "→ Waiting for container to start..."
sleep 5

# Show logs
echo "→ Container logs:"
echo "=========================================="
docker compose logs smtp-relay --tail=30

echo ""
echo "=========================================="
echo "✓ Deployment complete!"
echo "=========================================="
echo ""
echo "Now test from AMS with:"
echo "  Host: linenarrow.com"
echo "  Port: 2587"
echo ""
echo "Check logs with:"
echo "  docker compose logs smtp-relay -f"
echo "  docker compose logs api -f"
echo "=========================================="
