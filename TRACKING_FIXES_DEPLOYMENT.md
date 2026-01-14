# Tracking & Campaign Fixes - Deployment Guide

## Problem Summary

After testing a campaign (ID: 98) with 5 emails, the following issues were discovered:

1. ❌ **Links not replaced** with tracking URLs
2. ❌ **Opens not tracked** (no tracking pixel)
3. ❌ **No unsubscribe links** visible in emails
4. ❌ **Auto-stop didn't work** when bounces occurred
5. ❌ **Emails looked standalone** (no campaign context)

## Root Cause

**The Docker images were not rebuilt after code changes**, so the running containers were still using the old code.

### Why This Happened

The API and Sidekiq services use `build:` in docker-compose.yml, which means:
- Source code is **compiled into Docker images**
- Code is **NOT mounted as a volume**
- Changes require **rebuilding images** to take effect

## Fixes Implemented

Three critical fixes were made on 2026-01-14:

### 1. Fixed ErrorClassifier Constant Error (09:08:45)
**File:** `services/api/app/services/error_classifier.rb`
**Commit:** `23eb570`

**Problem:** `CheckMailingThresholdsJob` referenced `ErrorClassifier::STOP_MAILING_CATEGORIES` constant that no longer exists (moved to YAML).

**Fix:** Added public method `stop_mailing_categories` to ErrorClassifier:
```ruby
def stop_mailing_categories
  config['stop_mailing_categories'] || []
end
```

**Impact:** Auto-stop mechanism now works when critical bounces occur.

---

### 2. Enabled Click and Open Tracking (09:09:12)
**File:** `services/api/app/services/postal_client.rb`
**Commit:** `2f21e06`

**Problem:** PostalClient wasn't sending tracking flags to Postal API.

**Fix:** Added tracking flags to API request:
```ruby
body: {
  # ... other fields ...
  bounce: true,
  track_clicks: true,   # NEW
  track_opens: true     # NEW
}
```

**Impact:** Postal now replaces links with tracking URLs and injects open tracking pixel.

---

### 3. Pass campaign_id to PostalClient (09:12:51)
**File:** `services/api/app/jobs/send_smtp_email_job.rb`
**Commit:** `df8bd07`

**Problem:** Campaign ID was saved in EmailLog but not passed to Postal, so emails lost campaign context.

**Fix:** Added campaign_id to payload:
```ruby
postal_payload = {
  to: envelope[:to].is_a?(Array) ? envelope[:to].first : envelope[:to],
  from: envelope[:from],
  subject: message[:subject],
  html_body: html_content,
  headers: build_custom_headers(message),
  tag: 'smtp-relay',
  campaign_id: email_log.campaign_id  # NEW
}
```

**Impact:** Postal now knows the campaign context, enabling proper unsubscribe links in headers.

---

## Deployment Instructions

### Step 1: Deploy the Fixes

Run the deployment script:
```bash
./deploy-tracking-fixes.sh
```

This script will:
1. Rebuild API and Sidekiq Docker images with latest code
2. Recreate containers with new images
3. Wait for services to be healthy
4. Show deployment status

**Expected time:** 2-3 minutes

---

### Step 2: Verify Deployment

Run the verification script:
```bash
./verify-tracking-fixes.sh
```

This checks:
- ✓ ErrorClassifier method exists
- ✓ PostalClient has tracking flags
- ✓ SendSmtpEmailJob passes campaign_id
- ✓ Recent EmailLog records
- ✓ Campaign statistics
- ✓ Bounce patterns configuration

---

### Step 3: Test with Real Campaign

1. **Create a new test campaign** in AMS with:
   - At least 2 real email addresses (yours)
   - 1 fake address for bounce testing (e.g., `fake@nonexistentdomain123456.com`)

2. **Set the header** in AMS:
   ```
   X-ID-mail: [%%MailingID%%]
   ```

3. **Include a link** in the email body (e.g., `https://example.com`)

4. **Send the campaign** and wait for delivery

5. **Check your inbox** and verify:
   - [ ] Links are replaced with tracking URLs (e.g., `https://yourdomain.com/track/click/...`)
   - [ ] Email headers contain `List-Unsubscribe` with your domain
   - [ ] Opening email creates tracking event (check Dashboard)
   - [ ] Clicking link creates tracking event (check Dashboard)

6. **Check Error Monitor** for the fake address:
   - [ ] Bounce is recorded
   - [ ] Bounce category is classified (e.g., `mailbox_not_found`)
   - [ ] If critical category, campaign should auto-stop

---

## Troubleshooting

### Links Still Not Tracked

**Check if Postal tracking is enabled:**
```bash
docker compose exec postal cat /opt/postal/config/postal.yml | grep track_domain
```

Should show: `track_domain: yourdomain.com`

**Check if links exist in HTML:**
Tracking only works if the email body contains `<a href="...">` tags.

---

### Opens Not Tracked

**Check if email is HTML:**
Open tracking requires HTML body (tracking pixel is an image tag).

**Check if images are allowed:**
Some email clients block images by default.

---

### Campaign ID Not Associated

**Check EmailLog:**
```bash
docker compose exec api rails runner "puts EmailLog.last.campaign_id"
```

Should output the campaign ID (e.g., "98"), not nil.

**Check header extraction:**
```bash
docker compose logs api | grep "Extracted campaign_id"
```

Should show extracted campaign ID from X-ID-mail header.

---

### Auto-Stop Not Working

**Check MailingRule:**
```bash
docker compose exec api rails runner "rule = MailingRule.instance; puts 'Active: ' + rule.active?.to_s; puts 'Auto-stop: ' + rule.auto_stop_mailing?.to_s"
```

**Check DeliveryError records:**
```bash
docker compose exec api rails runner "puts DeliveryError.order(created_at: :desc).limit(5).pluck(:campaign_id, :category, :created_at)"
```

**Check Sidekiq critical queue:**
```bash
docker compose logs sidekiq | grep CheckMailingThresholdsJob
```

---

## Files Modified

| File | Purpose | Lines Changed |
|------|---------|---------------|
| `services/api/app/services/error_classifier.rb` | Add stop_mailing_categories method | +5 |
| `services/api/app/jobs/check_mailing_thresholds_job.rb` | Use method instead of constant | 2 |
| `services/api/app/services/postal_client.rb` | Enable tracking flags | +2 |
| `services/api/app/jobs/send_smtp_email_job.rb` | Pass campaign_id | +1 |

**Total:** 10 lines changed across 4 files

---

## Testing Checklist

- [ ] Run `./deploy-tracking-fixes.sh` successfully
- [ ] Run `./verify-tracking-fixes.sh` - all checks pass
- [ ] Send test campaign with real addresses
- [ ] Verify links are tracking URLs in received email
- [ ] Verify List-Unsubscribe header exists
- [ ] Click link and confirm tracking event recorded
- [ ] Open email and confirm open event recorded
- [ ] Send to fake address and verify bounce classification
- [ ] Verify auto-stop works for critical bounce categories

---

## Rollback Plan

If issues occur, rollback to previous version:

```bash
# Revert code changes
git revert df8bd07 2f21e06 23eb570

# Rebuild and restart
docker compose build api sidekiq
docker compose up -d --force-recreate api sidekiq
```

---

## Support

If issues persist after deployment:

1. **Check logs:**
   ```bash
   docker compose logs -f api sidekiq postal
   ```

2. **Check Postal suppression list:**
   - Log into Postal web interface
   - Go to suppression list
   - Remove test email addresses if blocked

3. **Verify Postal webhook signature:**
   - Currently disabled (`SKIP_POSTAL_WEBHOOK_VERIFICATION=true`)
   - If re-enabling, ensure public key is correctly configured

---

## Related Documentation

- [BOUNCE_PATTERNS_SIMPLE_PLAN.md](./BOUNCE_PATTERNS_SIMPLE_PLAN.md) - Bounce patterns management
- [QUICKSTART.md](./QUICKSTART.md) - General setup guide
- [Makefile](./Makefile) - Common operations

---

**Last Updated:** 2026-01-14
**Status:** Ready for deployment
**Branch:** `claude/bounce-patterns-management-Awt4F`
