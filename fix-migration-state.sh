#!/bin/bash
# Script to fix migration state for email tracking tables
# Run this on your server where Docker is available

set -e

echo "=== Checking Migration State ==="

# Check which migrations have been applied
echo "1. Checking applied migrations..."
docker compose exec -T postgres psql -U postal -d postal -c "SELECT version FROM schema_migrations WHERE version LIKE '202601%' ORDER BY version;" || true

# Check if tables exist
echo ""
echo "2. Checking if email_clicks table exists..."
docker compose exec -T postgres psql -U postal -d postal -c "\d email_clicks" || echo "Table does not exist"

echo ""
echo "3. Checking if email_opens table exists..."
docker compose exec -T postgres psql -U postal -d postal -c "\d email_opens" || echo "Table does not exist"

echo ""
echo "=== Fixing Migration State ==="

# Option 1: If tables exist but migrations are not recorded, mark them as complete
echo "4. Marking migrations as complete (if tables exist)..."
docker compose exec -T api rails runner "
begin
  # Check if tables exist
  tables_exist = ActiveRecord::Base.connection.table_exists?(:email_clicks) &&
                 ActiveRecord::Base.connection.table_exists?(:email_opens)

  if tables_exist
    puts 'Tables exist, marking migrations as complete...'

    # Mark migrations as complete
    ActiveRecord::Base.connection.execute(
      \"INSERT INTO schema_migrations (version) VALUES ('20260114180000') ON CONFLICT DO NOTHING\"
    )
    ActiveRecord::Base.connection.execute(
      \"INSERT INTO schema_migrations (version) VALUES ('20260114180100') ON CONFLICT DO NOTHING\"
    )

    puts 'Migrations marked as complete'
  else
    puts 'Tables do not exist, migrations will run normally'
  end
rescue => e
  puts \"Error: #{e.message}\"
  puts 'Will try to run migrations normally...'
end
"

echo ""
echo "5. Running all pending migrations..."
docker compose exec -T api rails db:migrate RAILS_ENV=production

echo ""
echo "=== Verifying Migration State ==="
echo "6. Checking final migration state..."
docker compose exec -T postgres psql -U postal -d postal -c "SELECT version FROM schema_migrations WHERE version LIKE '202601%' ORDER BY version;"

echo ""
echo "7. Verifying tables exist..."
docker compose exec -T postgres psql -U postal -d postal -c "\d email_clicks" | head -20
echo ""
docker compose exec -T postgres psql -U postal -d postal -c "\d email_opens" | head -20

echo ""
echo "=== Restarting Containers ==="
echo "8. Restarting API and Sidekiq..."
docker compose restart api sidekiq

echo ""
echo "9. Waiting for containers to be healthy..."
sleep 5

echo ""
echo "10. Checking container status..."
docker compose ps

echo ""
echo "=== Migration Fix Complete ==="
echo "If all containers are healthy, the tracking system is ready to use!"
