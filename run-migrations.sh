#!/bin/bash

# Script to run pending database migrations for API service
# This will run migrations 006, 007, and 008 to create smtp_credentials and webhook_endpoints tables

set -e

echo "Running database migrations for API service..."

# Run migrations via docker-compose
docker compose exec api bundle exec rails db:migrate

echo "✅ Database migrations completed successfully!"
echo ""
echo "The following tables should now be created:"
echo "  - smtp_credentials (migration 006)"
echo "  - webhook_endpoints (migration 007)"
echo "  - webhook_logs (migration 008)"
echo ""
echo "You can now access the Settings page and API Keys section without errors."
