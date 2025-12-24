#!/bin/bash
set -e

cd /app

# Use RAILS_ENV from environment or default to development
RAILS_ENV=${RAILS_ENV:-development}

echo "Initializing database for environment: $RAILS_ENV"

bundle exec rails db:create RAILS_ENV=$RAILS_ENV
bundle exec rails db:migrate RAILS_ENV=$RAILS_ENV

echo "Database initialized successfully"

