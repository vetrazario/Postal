#!/bin/bash
set -e

cd /app

# Extract host and port from DATABASE_URL
DB_HOST=$(echo $DATABASE_URL | sed -e 's|.*@\(.*\):.*|\1|')
DB_PORT=$(echo $DATABASE_URL | sed -e 's|.*:\([0-9]*\)/.*|\1|')

# Wait for database to be ready using timeout and bash
echo "Waiting for database at $DB_HOST:$DB_PORT..."
max_attempts=30
attempt=0
until timeout 2 bash -c "echo > /dev/tcp/$DB_HOST/$DB_PORT" 2>/dev/null; do
  attempt=$((attempt + 1))
  if [ $attempt -ge $max_attempts ]; then
    echo "Database connection timed out after $max_attempts attempts"
    exit 1
  fi
  echo "Database is unavailable - sleeping (attempt $attempt/$max_attempts)"
  sleep 2
done
echo "Database is ready"

# Additional wait for PostgreSQL to be fully ready
sleep 3

# Run migrations
echo "Running database migrations..."
bundle exec rails db:migrate || {
  echo "Migration failed!"
  exit 1
}

echo "Migrations completed successfully"

# Execute the main command
exec "$@"

