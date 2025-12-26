#!/bin/bash
# ===========================================
# Deploy API Key Fix
# ===========================================
# Fixes POSTAL_API_KEY environment variable
# to use correct API key instead of signing key
# ===========================================

set -e

echo "=========================================="
echo "DEPLOYING POSTAL API KEY FIX"
echo "=========================================="

# Pull latest changes
echo "Pulling latest changes..."
git pull origin claude/setup-email-testing-YifKd

# Verify the .env has both keys set
echo ""
echo "Verifying environment variables..."
if ! grep -q "^POSTAL_API_KEY=" .env || [ -z "$(grep '^POSTAL_API_KEY=' .env | cut -d'=' -f2)" ]; then
    echo "ERROR: POSTAL_API_KEY is not set in .env"
    echo "Please set it to your Postal mail server API key"
    exit 1
fi

if ! grep -q "^POSTAL_SIGNING_KEY=" .env || [ -z "$(grep '^POSTAL_SIGNING_KEY=' .env | cut -d'=' -f2)" ]; then
    echo "ERROR: POSTAL_SIGNING_KEY is not set in .env"
    exit 1
fi

echo "✓ POSTAL_API_KEY: $(grep '^POSTAL_API_KEY=' .env | cut -d'=' -f2)"
echo "✓ POSTAL_SIGNING_KEY: $(grep '^POSTAL_SIGNING_KEY=' .env | cut -d'=' -f2)"

# Rebuild and restart affected containers
echo ""
echo "Rebuilding api and sidekiq containers..."
docker compose build api sidekiq

echo ""
echo "Restarting containers..."
docker compose up -d api sidekiq

# Wait for services to be ready
echo ""
echo "Waiting 15 seconds for services to start..."
sleep 15

# Check container status
echo ""
echo "Container status:"
docker compose ps | grep -E "(api|sidekiq)"

# Verify environment variable in running container
echo ""
echo "Verifying POSTAL_API_KEY in api container:"
docker compose exec api env | grep POSTAL_API_KEY

echo ""
echo "=========================================="
echo "DEPLOYMENT COMPLETE!"
echo "=========================================="
echo ""
echo "The api and sidekiq containers are now using"
echo "the correct POSTAL_API_KEY from .env"
echo ""
echo "Previous issue: Used POSTAL_SIGNING_KEY (wrong!)"
echo "Fixed: Now uses POSTAL_API_KEY (correct!)"
echo ""
echo "Next step: Send a test email from AMS Enterprise"
echo "=========================================="
