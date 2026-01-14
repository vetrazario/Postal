# 🚀 Quick Fix - Tracking Not Working

## Problem
Campaign tracking не работает потому что **Docker images не были пересобраны после изменения кода**.

## Solution (2 commands)

```bash
# 1. Deploy fixes (rebuild + restart)
./deploy-tracking-fixes.sh

# 2. Verify deployment
./verify-tracking-fixes.sh
```

## What This Does

### Deploy Script:
1. ✓ Rebuilds API and Sidekiq images with latest code
2. ✓ Restarts containers
3. ✓ Waits for healthy status
4. ✓ Shows verification logs

### Verify Script:
1. ✓ Checks ErrorClassifier method exists
2. ✓ Checks PostalClient has tracking flags
3. ✓ Checks SendSmtpEmailJob passes campaign_id
4. ✓ Shows recent EmailLog records
5. ✓ Shows campaign statistics

## After Deployment

Test with new campaign:

```bash
# Send campaign from AMS with header:
# X-ID-mail: [%%MailingID%%]

# Then check:
```

### 1. Check received email
- Links should be tracking URLs: `https://linenarrow.com/track/click/...`
- Headers should have `List-Unsubscribe: <https://linenarrow.com/unsubscribe?...>`

### 2. Check Dashboard
- Opens should increment when email opened
- Clicks should increment when link clicked

### 3. Check Error Monitor
- Send to fake address: `fake@nonexistent12345.com`
- Bounce should be classified (category, SMTP code)
- If critical category → campaign should auto-stop

## What Was Fixed

| Issue | Fix | File |
|-------|-----|------|
| Auto-stop error | Added `stop_mailing_categories` method | error_classifier.rb |
| Links not tracked | Added `track_clicks: true` | postal_client.rb |
| Opens not tracked | Added `track_opens: true` | postal_client.rb |
| No campaign context | Pass `campaign_id` parameter | send_smtp_email_job.rb |

## Troubleshooting

### Still not working?

**1. Check Postal suppression list:**
Your test emails might be blocked in Postal's suppression list.

```bash
# Access Postal web interface
https://linenarrow.com/postal/

# Remove addresses from suppression list
```

**2. Check logs:**
```bash
docker compose logs -f api sidekiq | grep -i "track\|campaign"
```

**3. Check if new code is running:**
```bash
docker compose exec api rails runner "puts File.read('app/services/postal_client.rb').include?('track_clicks: true')"
```
Should output: `true`

## Documentation

Full details: [TRACKING_FIXES_DEPLOYMENT.md](./TRACKING_FIXES_DEPLOYMENT.md)

---

**TL;DR:** Run `./deploy-tracking-fixes.sh` then test new campaign
