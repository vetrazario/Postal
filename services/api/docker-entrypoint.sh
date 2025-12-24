#!/bin/bash
set -e

cd /app

# Wait for database to be ready
echo "Waiting for database to be ready..."
until bundle exec rails runner "ActiveRecord::Base.connection" 2>/dev/null; do
  echo "Database is unavailable - sleeping"
  sleep 2
done
echo "Database is ready"

# Run migrations
echo "Running database migrations..."
bundle exec rails db:migrate || {
  echo "Migration failed!"
  exit 1
}

echo "Migrations completed successfully"

# Execute the main command
exec "$@"

