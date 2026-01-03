# Fix: Correct Postal Container Configuration

## 📋 Problem

The Postal container had an incorrect startup command:
```yaml
command: >
  sh -c "
    postal initialize-db || true &&
    postal web-server &
    postal smtp-server &
    postal worker &
    wait
  "
```

This caused:
1. ❌ `postal initialize-db` to ignore ENV variables from docker-compose.yml
2. ❌ Use default local socket connection (`/run/mysqld/mysqld.sock`) instead of TCP
3. ❌ Inconsistent and unpredictable behavior (manual initialization vs auto)
4. ❌ Required manual config file `config/postal.yml` with hardcoded values

## ✅ Solution

### 1. Simplified Command

Use the standard `postal boot` command which:
- ✅ Automatically initializes DB on first run using ENV variables
- ✅ Uses correct TCP connection to MariaDB from ENV
- ✅ No need for manual `initialize-db`
- ✅ Predictable and maintainable behavior

```yaml
command: ["postal", "boot"]
```

### 2. Remove Config File

No longer need `config/postal.yml` because:
- ✅ All database settings provided via ENV variables in docker-compose.yml
- ✅ No hardcoded values
- ✅ Single source of truth: docker-compose.yml + .env file
- ✅ Easier to maintain and debug

### 3. Updated Volume Mount

```yaml
volumes:
  # Postal configuration via ENV variables (no config file needed)
  - postal_data:/opt/postal/data
```

## 📝 File Changes

### docker-compose.yml

**Before:**
```yaml
postal:
  command: >
    sh -c "
      postal initialize-db || true &&
      postal web-server &
      postal smtp-server &
      postal worker &
      wait
    "
  volumes:
    - ./config/postal.yml:/opt/postal/config/postal.yml:ro
    - postal_data:/opt/postal/data
```

**After:**
```yaml
postal:
  # Postal automatically initializes DB on first run using ENV variables
  # No manual 'initialize-db' needed - it's handled by docker-entrypoint.sh
  command: ["postal", "boot"]
  volumes:
    # Postal configuration via ENV variables (no config file needed)
    - postal_data:/opt/postal/data
```

### config/postal.yml

**Status:** ❌ Deleted (no longer needed)

Reason: All database settings are now provided via ENV variables in docker-compose.yml

## 🎯 Benefits

1. **Simplicity:** Single source of configuration (docker-compose.yml + .env)
2. **Maintainability:** No hardcoded values to keep in sync
3. **Consistency:** All containers use same .env variables
4. **Predictability:** Standard Postal boot behavior
5. **Debuggability:** Easy to see actual configuration via ENV variables

## 📚 Documentation

Reference: https://docs.postalserver.io/

Postal Boot Process:
1. Reads `POSTAL_MAIN_DB_HOST`, `POSTAL_MAIN_DB_PASSWORD`, etc. from ENV
2. Connects to MariaDB via TCP (host: mariadb, port: 3306)
3. Initializes database schema if not exists
4. Starts web-server, smtp-server, and worker processes

## 🧪 Verification

After deployment, verify:

```bash
# Check container is healthy
docker compose ps | grep postal

# Check logs show no DB connection errors
docker compose logs postal --tail=30 | grep -i "error\|fail" || echo "✅ No errors"

# Check postal is accessible
curl -I https://postal.linenarrow.com/
```

## 🔄 Migration Path

### Old (Broken)
1. Manual DB initialization with defaults
2. Override with config file
3. Hardcoded values

### New (Fixed)
1. Automatic DB initialization via ENV variables
2. No config file needed
3. Single source of truth

