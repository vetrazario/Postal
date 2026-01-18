# Migration Fix Guide

## Problem
The migration failed with error:
```
PG::DuplicateTable: ERROR: relation "index_email_opens_on_email_log_id" already exists
```

This happens when tables were partially created in a previous deployment attempt but migrations were not recorded in the `schema_migrations` table.

## Solution

### Automated Fix (Recommended)

Run the automated fix script on your server:

```bash
cd /path/to/Postal
./fix-migration-state.sh
```

This script will:
1. Check current migration state
2. Verify if tables exist
3. Mark completed migrations in schema_migrations
4. Run any pending migrations
5. Restart containers
6. Verify everything is working

### Manual Fix (If Script Fails)

If the automated script doesn't work, follow these steps:

#### Step 1: Check Current State

```bash
# Check which migrations are recorded
docker compose exec -T postgres psql -U postal -d postal -c \
  "SELECT version FROM schema_migrations WHERE version LIKE '202601%' ORDER BY version;"

# Check if tables exist
docker compose exec -T postgres psql -U postal -d postal -c "\d email_clicks"
docker compose exec -T postgres psql -U postal -d postal -c "\d email_opens"
```

#### Step 2: Mark Migrations as Complete (If Tables Exist)

If tables exist but migrations are not in schema_migrations:

```bash
docker compose exec -T api rails runner "
  ActiveRecord::Base.connection.execute(
    \\\"INSERT INTO schema_migrations (version) VALUES ('20260114180000') ON CONFLICT DO NOTHING\\\"
  )
  ActiveRecord::Base.connection.execute(
    \\\"INSERT INTO schema_migrations (version) VALUES ('20260114180100') ON CONFLICT DO NOTHING\\\"
  )
  puts 'Migrations marked as complete'
"
```

#### Step 3: Run Pending Migrations

```bash
docker compose exec -T api rails db:migrate RAILS_ENV=production
```

#### Step 4: Restart Containers

```bash
docker compose restart api sidekiq
```

#### Step 5: Verify

```bash
# Check container health
docker compose ps

# Check migrations
docker compose exec -T postgres psql -U postal -d postal -c \
  "SELECT version FROM schema_migrations WHERE version LIKE '202601%' ORDER BY version;"

# Should show:
# 20260114180000 (create_email_clicks)
# 20260114180100 (create_email_opens)
# 20260115000000 (allow_null_tracking_timestamps)
# 20260116000000 (add_ip_address_indexes_for_performance)
```

### Alternative: Drop and Recreate (Nuclear Option)

**WARNING**: This will delete all tracking data! Only use if:
- Tables are corrupted
- Other methods failed
- You have no important tracking data to preserve

```bash
# Drop tracking tables
docker compose exec -T postgres psql -U postal -d postal -c "DROP TABLE IF EXISTS email_clicks CASCADE;"
docker compose exec -T postgres psql -U postal -d postal -c "DROP TABLE IF EXISTS email_opens CASCADE;"

# Remove migration records
docker compose exec -T postgres psql -U postal -d postal -c \
  "DELETE FROM schema_migrations WHERE version IN ('20260114180000', '20260114180100', '20260115000000', '20260116000000');"

# Run migrations fresh
docker compose exec -T api rails db:migrate RAILS_ENV=production

# Restart containers
docker compose restart api sidekiq
```

## Expected Final State

After successful fix, you should see:

### 1. All migrations recorded:
```
     version
----------------
 20260114180000
 20260114180100
 20260115000000
 20260116000000
```

### 2. Both tables exist:
```bash
$ docker compose exec -T postgres psql -U postal -d postal -c "\d email_clicks"
                                         Table "public.email_clicks"
    Column    |              Type              | Collation | Nullable |                  Default
--------------+--------------------------------+-----------+----------+--------------------------------------------
 id           | bigint                         |           | not null | nextval('email_clicks_id_seq'::regclass)
 email_log_id | bigint                         |           | not null |
 campaign_id  | character varying              |           | not null |
 url          | character varying(2048)        |           | not null |
 ip_address   | character varying              |           |          |
 user_agent   | character varying(1024)        |           |          |
 token        | character varying              |           | not null |
 clicked_at   | timestamp without time zone    |           |          |
 created_at   | timestamp(6) without time zone |           | not null |
 updated_at   | timestamp(6) without time zone |           | not null |
```

### 3. All containers healthy:
```bash
$ docker compose ps
NAME           STATUS
email_api      Up (healthy)
email_sidekiq  Up
postgres       Up (healthy)
redis          Up (healthy)
```

## Testing After Fix

Once migrations are complete and containers are healthy:

```bash
# Test that models load correctly
docker compose exec api rails runner "
  puts 'EmailClick count: ' + EmailClick.count.to_s
  puts 'EmailOpen count: ' + EmailOpen.count.to_s
  puts 'Models loaded successfully!'
"
```

If you see the counts (should be 0 initially), the tracking system is ready!
