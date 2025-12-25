# QUICK TESTING GUIDE

## ✅ Configuration Status

All configuration files are correctly set up:
- ✓ `.env` created with generated secrets (4.6KB)
- ✓ `config/postal.yml` has real passwords (no ${VARIABLE} placeholders)
- ✓ `config/htpasswd` created for Basic Auth
- ✓ `config/nginx.conf` updated with Postal proxy

## 🧪 Testing Steps

### 1. Start All Services

```bash
cd /home/user/Postal

# Start databases first
docker compose up -d postgres mariadb redis rabbitmq

# Wait for databases to initialize (60 seconds)
sleep 60

# Check database health
docker compose exec postgres pg_isready -U email_sender
docker compose exec mariadb mysqladmin ping -u postal -pfc83da74d27a7b12e990eba01b0410a1
docker compose exec redis redis-cli ping

# Start all services
docker compose up -d

# Check status
docker compose ps
```

### 2. Initialize Postal

```bash
# Initialize Postal database
docker compose exec postal postal initialize

# Expected output: "Database initialized successfully"

# Create admin user
docker compose exec postal postal make-user
```

**Enter these details:**
- Email: `admin@linenarrow.com`
- First name: `Admin`
- Last name: `User`
- Password: `[create strong password]` ← **SAVE THIS!**

### 3. Access Postal Web UI

**URL:** `http://localhost/postal/` (or `http://localhost:5000`)

**Login:**
- Username: `admin@linenarrow.com`
- Password: `[password from step 2]`

**Basic Auth (if prompted):**
- Username: `admin`
- Password: `DBbNm9X11lHVivPI`

### 4. Create Organization & Mail Server

**This should NOT hang anymore!**

1. Click **"Create Organization"**
   - Name: `LineNarrow`
   - Click **Create**

2. Click **"Create Mail Server"**
   - Name: `Send Server 1`
   - Mode: `Live`
   - Click **Create**

**✓ SUCCESS:** If mail server creates without hanging, the fix worked!

3. Add Domain:
   - Click **"Domains"** → **"Add Domain"**
   - Domain: `linenarrow.com`
   - Click **Create**

4. Get DKIM Record:
   ```bash
   docker compose exec postal postal default-dkim-record
   ```

   **Add this TXT record to your DNS.**

5. Create API Credential:
   - Click **"Credentials"** → **"Create Credential"**
   - Type: `API`
   - Name: `Send Server API`
   - Click **Create**
   - **COPY THE API KEY** (shown only once!)

6. Update .env with Postal API Key:
   ```bash
   nano .env
   # Add line:
   # POSTAL_API_KEY=proj_xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
   ```

   ```bash
   # Restart services
   docker compose restart api sidekiq
   ```

### 5. Initialize Rails API

```bash
# Create database
docker compose exec api rails db:create

# Run migrations
docker compose exec api rails db:migrate

# Create API key for AMS
docker compose exec api rails runner "
  api_key, raw_key = ApiKey.generate(name: 'AMS Production')
  puts '=' * 60
  puts 'API KEY FOR AMS:'
  puts raw_key
  puts '=' * 60
  puts 'Save this - it will not be shown again!'
"
```

**SAVE THE API KEY!** This is what AMS will use to send emails.

### 6. Test Health Endpoints

```bash
# API Health
curl http://localhost/api/v1/health

# Expected: {"status":"healthy",...}

# Tracking Health
curl http://localhost/track/health

# Expected: {"status":"ok"}

# Postal Health
curl http://localhost:5000/health

# Expected: 200 OK
```

### 7. Send Test Email (HTTP API)

```bash
# Replace YOUR_API_KEY with the key from step 5
curl -X POST http://localhost/api/v1/send \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "recipient": "test@example.com",
    "from_name": "Test Sender",
    "from_email": "sender@linenarrow.com",
    "subject": "Test Email",
    "variables": {
      "body": "<h1>Hello!</h1><p>This is a test email.</p>"
    },
    "tracking": {
      "campaign_id": "test_campaign_001",
      "message_id": "test_msg_001"
    }
  }'
```

**Expected Response:**
```json
{
  "status": "queued",
  "message_id": "local_abc123def456",
  "external_message_id": "test_msg_001"
}
```

### 8. Check Email Status

```bash
curl -H "Authorization: Bearer YOUR_API_KEY" \
  http://localhost/api/v1/status/test_msg_001
```

**Expected Response:**
```json
{
  "message_id": "test_msg_001",
  "status": "delivered",
  "recipient": "t***@example.com",
  ...
}
```

## ✅ Success Criteria

- [x] Configuration files created correctly
- [ ] Docker containers all running
- [ ] Postal initialized without errors
- [ ] Can create Organization in Postal UI
- [ ] Can create Mail Server **WITHOUT HANGING** ← Main fix!
- [ ] Can add domain to mail server
- [ ] DKIM record generated
- [ ] API credential created
- [ ] Rails database initialized
- [ ] API key created
- [ ] Health endpoints respond
- [ ] Test email queued successfully
- [ ] Email status retrievable

## 🐛 Troubleshooting

### Postal hangs when creating mail server
**Status:** Should be FIXED now!

If still happens:
```bash
# Check Postal logs
docker compose logs postal | tail -50

# Check MariaDB connection
docker compose exec postal postal config-test
```

### Database connection errors
```bash
# Verify passwords in .env match postal.yml
grep MARIADB_PASSWORD .env
grep "password:" config/postal.yml

# Should match!
```

### API 500 errors
```bash
# Check Rails logs
docker compose logs api | tail -50

# Check Sidekiq
docker compose exec api rails runner "require 'sidekiq/api'; puts Sidekiq::Stats.new.inspect"
```

### Postal API errors
```bash
# Verify POSTAL_API_KEY is set
grep POSTAL_API_KEY .env

# Restart services
docker compose restart api sidekiq
```

## 📊 View Logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f postal
docker compose logs -f api
docker compose logs -f sidekiq

# Last 100 lines
docker compose logs --tail=100 postal
```

## 🎯 Next Steps After Testing

Once testing is complete and everything works:

1. **Configure DNS records** (if going to production)
2. **Set up SSL certificates** (Let's Encrypt)
3. **Proceed with Phase 2-6 implementation:**
   - SMTP Relay with Haraka
   - Dashboard UI
   - AI Analytics
   - Complete email flow

---

**Testing Status:** Ready to begin
**Estimated Time:** 30-60 minutes
**Success Rate:** Should be 100% with fixed configuration
