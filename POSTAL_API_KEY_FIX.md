# Postal API Key Fix

## Problem Summary

The Postal API was returning **403 Forbidden** when trying to send emails. The complete email flow was working up to the point where Sidekiq tried to send through Postal.

### Root Cause

The `docker-compose.yml` configuration had **incorrect environment variable mapping**:

```yaml
# WRONG (before fix):
environment:
  POSTAL_API_KEY: ${POSTAL_SIGNING_KEY}  # ❌ Using signing key instead of API key!
```

This caused the API and Sidekiq containers to use `POSTAL_SIGNING_KEY` value when making Postal API requests, but Postal expects the actual `POSTAL_API_KEY`.

### Two Different Keys

In `.env` there are TWO different Postal keys:

1. **POSTAL_SIGNING_KEY** - Internal signing key for Postal server
   - Value: `fb0a011d0deca205f41e56848c509f402849d1ba56c9e60e8983c74377e514dc`
   - Used internally by Postal for cryptographic operations

2. **POSTAL_API_KEY** - Mail server API key for making API requests
   - Value: `FSJbztugA0ZmzAiF6GWWOtnv`
   - Used by our application to send emails via Postal API
   - Generated in Postal Web UI: Mail Server → Credentials → API Keys

### Error Flow

```
AMS Enterprise
  ↓ (SMTP to port 2587)
Haraka SMTP Relay ✓
  ↓ (HTTP POST to /api/v1/smtp/receive)
Rails API ✓
  ↓ (Queue job)
Sidekiq ✓
  ↓ (Call PostalClient)
PostalClient ✓
  ↓ (HTTP POST with X-Server-API-Key: WRONG_KEY)
Postal API ✗ → 403 Forbidden
```

## Solution

### Fixed Configuration

```yaml
# CORRECT (after fix):
environment:
  POSTAL_API_KEY: ${POSTAL_API_KEY}  # ✅ Using correct API key!
  POSTAL_SIGNING_KEY: ${POSTAL_SIGNING_KEY}
```

### Files Changed

- **docker-compose.yml** - Fixed environment variable mapping (2 places: api and sidekiq services)

### Commit

```
commit 37a2227
Fix POSTAL_API_KEY environment variable mapping

- Changed POSTAL_API_KEY to use ${POSTAL_API_KEY} instead of ${POSTAL_SIGNING_KEY}
- This fixes 403 Forbidden error when calling Postal API
- The signing key and API key are different and should not be mixed
```

## Deployment Instructions

### 1. SSH to Server

```bash
ssh root@159.255.39.48
cd /root/Postal
```

### 2. Run Deployment Script

```bash
./deploy-api-key-fix.sh
```

The script will:
1. Pull latest changes from branch `claude/setup-email-testing-YifKd`
2. Verify both keys are set in `.env`
3. Rebuild `api` and `sidekiq` containers
4. Restart the containers
5. Verify the correct API key is loaded

### 3. Manual Deployment (Alternative)

If you prefer manual steps:

```bash
# Pull changes
git pull origin claude/setup-email-testing-YifKd

# Verify .env has both keys
grep POSTAL_API_KEY .env
grep POSTAL_SIGNING_KEY .env

# Rebuild and restart
docker compose build api sidekiq
docker compose up -d api sidekiq

# Verify API key in container
docker compose exec api env | grep POSTAL_API_KEY
# Should show: POSTAL_API_KEY=FSJbztugA0ZmzAiF6GWWOtnv
```

## Testing

### 1. Send Test Email from AMS Enterprise

Configure SMTP in AMS:
- Server: `linenarrow.com` (or `159.255.39.48`)
- Port: `2587`
- From: `test@linenarrow.com`
- To: `zillatraffic@gmail.com`
- Authentication: As configured

### 2. Monitor Logs

```bash
# Watch all relevant services
docker compose logs -f smtp-relay api sidekiq postal

# Or check each separately:
docker compose logs -f smtp-relay  # Should show: 250 Message accepted
docker compose logs -f api         # Should show: status: 'queued'
docker compose logs -f sidekiq     # Should show: SMTP email sent successfully
docker compose logs -f postal      # Should show: 200 OK (not 403!)
```

### 3. Expected Success Flow

```
1. AMS sends email to SMTP relay (port 2587)
   → Log: "Message accepted for delivery"

2. SMTP relay forwards to Rails API
   → Log: "SMTP receive payload: {...}"
   → Response: { status: 'queued', message_id: 'smtp_...' }

3. Sidekiq picks up job
   → Log: "Performing SendSmtpEmailJob"

4. Job calls PostalClient.send_message()
   → Log: "POST /api/v1/send/message HTTP/1.1" 200 ✓

5. EmailLog updated to 'sent'
   → Log: "SMTP email sent successfully"

6. Email arrives in zillatraffic@gmail.com inbox ✓
```

### 4. Check Dashboard

Visit: `http://linenarrow.com:3000/dashboard`

- Login with credentials from `.env`
- Navigate to "Email Logs"
- Find your test email
- Status should be: **sent** (not failed!)
- Click to see details including Postal message ID

## Verification Checklist

- [ ] Containers rebuilt and restarted successfully
- [ ] `POSTAL_API_KEY=FSJbztugA0ZmzAiF6GWWOtnv` in container (not the signing key)
- [ ] Test email sent from AMS
- [ ] Postal API returns 200 OK (not 403)
- [ ] EmailLog status changes to 'sent'
- [ ] Email appears in recipient inbox
- [ ] Dashboard shows correct status

## Troubleshooting

### If Still Getting 403

The `POSTAL_API_KEY` in `.env` might not be the correct mail server API key.

**To get the correct key:**

1. Open Postal web UI: `http://linenarrow.com:5000`
2. Login with Postal credentials
3. Click on your mail server (e.g., "linenarrow")
4. Go to **Credentials** → **API Keys**
5. Create a new API key if needed
6. Copy the key and update `.env`:
   ```bash
   POSTAL_API_KEY=<your_mail_server_api_key>
   ```
7. Restart containers:
   ```bash
   docker compose restart api sidekiq
   ```

### If Email Not Arriving

1. Check Postal web UI → Messages to see if email was processed
2. Check spam folder in Gmail
3. Verify domain configuration in Postal
4. Check Postal logs for delivery errors

## Summary

**What was wrong:** Used `POSTAL_SIGNING_KEY` instead of `POSTAL_API_KEY`
**What was fixed:** Corrected environment variable mapping in docker-compose.yml
**Impact:** Postal API now accepts requests and emails can be sent
**Branch:** `claude/setup-email-testing-YifKd`
**Deployment:** Run `./deploy-api-key-fix.sh` on server
