# Tracking System Fixes - Summary

## Problems Fixed

### 1. ✅ Dashboard Overview Shows 0 Clicks (FIXED)

**Problem**: Dashboard overview displayed "Clicked: 0" despite successful clicks being recorded in EmailClick table.

**Root Cause**: `dashboard_controller.rb` was still using the old `TrackingEvent` model instead of the new `EmailClick` and `EmailOpen` models.

**Fix**:
- Updated `calculate_stats()` method in `services/api/app/controllers/dashboard/dashboard_controller.rb`
- Changed from: `TrackingEvent.where(email_log_id: logs.ids, event_type: 'click').count`
- Changed to: `EmailClick.where(email_log_id: logs.ids).where.not(clicked_at: nil).count`
- Same for opens: `EmailOpen.where(email_log_id: logs.ids).where.not(opened_at: nil).count`

**Result**: Dashboard overview will now correctly show click and open statistics.

---

### 2. 🔍 HTML Links Not Replaced with Tracking URLs (INVESTIGATION)

**Problem**:
- EmailClick records are created (proves `LinkTracker.create_tracking_url()` is called)
- But emails sent to recipients still contain original URLs (not tracking URLs)
- Tracking URLs work when manually visited
- Sidekiq logs show original HTML unchanged

**Investigation Added**:
Added extensive debug logging to identify where the HTML modification fails:

**In `LinkTracker.track_links()` (services/api/app/services/link_tracker.rb):**
- `[LinkTracker] Starting track_links` - confirms method is called
- `[LinkTracker] Found X links in HTML` - shows link detection
- `[LinkTracker] Skipping dangerous/special URL` - shows filtered links
- `[LinkTracker] Skipping own domain link` - shows internal links skipped
- `[LinkTracker] Replaced link X/Y: original -> tracking` - shows each replacement
- `[LinkTracker] Completed: tracked X links, HTML length: before -> after` - summary

**In `SendSmtpEmailJob.perform()` (services/api/app/jobs/send_smtp_email_job.rb):**
- `[SendSmtpEmailJob] Original HTML length: X, preview: ...` - input HTML
- `[SendSmtpEmailJob] Tracked HTML length: X, preview: ...` - output HTML
- `[SendSmtpEmailJob] HTML changed: true/false` - confirms modification
- `[SendSmtpEmailJob] Postal payload html_body preview: ...` - final payload

**Next Steps**:
1. Rebuild API container with new code
2. Send test email with a link (e.g., YouTube URL)
3. Check logs using `./check-tracking-debug.sh`
4. Logs will reveal exactly where the HTML modification fails

---

## Deployment Instructions

### Step 1: Pull Latest Changes
```bash
cd /home/user/Postal
git pull origin claude/project-analysis-errors-Awt4F
```

### Step 2: Rebuild API Container
```bash
# Stop API
docker compose stop api

# Remove container
docker compose rm -f api

# Rebuild with no cache
docker compose build --no-cache api

# Start all services
docker compose up -d

# Wait for services
sleep 10

# Verify Sidekiq is running
docker compose exec api bundle exec rails runner "puts Sidekiq::ProcessSet.new.size"
```

### Step 3: Test Dashboard Overview
1. Visit dashboard at https://linenarrow.com
2. Check if "Clicked" count is now showing correctly
3. If you had previous clicks, they should now appear

### Step 4: Test Email Tracking
1. Send a test email with a link (e.g., YouTube URL):
   ```bash
   # Use your existing SMTP test method
   ```

2. Check debug logs:
   ```bash
   ./check-tracking-debug.sh
   ```

3. Look for log entries like:
   ```
   [LinkTracker] Found 1 links in HTML
   [LinkTracker] Replaced link 1/1: https://www.youtube.com -> https://linenarrow.com/go/youtube-page-JAhY...
   [SendSmtpEmailJob] HTML changed: true
   ```

4. Check the email you received - it should have tracking URL like:
   ```
   https://linenarrow.com/go/youtube-page-JAhY6g9pD5tSzqfJ
   ```

---

## Diagnostic Scripts

### `check-tracking-debug.sh`
Shows tracking-related logs and statistics:
- LinkTracker and SendSmtpEmailJob debug logs
- Recent EmailClick records
- Dashboard overview stats

Usage:
```bash
./check-tracking-debug.sh
```

---

## Expected Log Output (After Fix)

### Successful Tracking Logs:
```
[LinkTracker] Starting track_links, track_clicks=true, max_links=10
[LinkTracker] Found 1 links in HTML
[LinkTracker] Replaced link 1/1: https://www.youtube.com/ -> https://linenarrow.com/go/youtube-page-JAhY6g9pD5tSzqfJ
[LinkTracker] Completed: tracked 1 links, HTML length: 150 -> 180
[SendSmtpEmailJob] Original HTML length: 150, preview: <html>...Это <a href="https://www.youtube.com/">ссылка</a>...
[SendSmtpEmailJob] Tracked HTML length: 180, preview: <html>...Esto <a href="https://linenarrow.com/go/youtube-page-JAhY6g9pD5tSzqfJ">ссылка</a>...
[SendSmtpEmailJob] HTML changed: true
```

### If Still Not Working:
If logs show:
- `[LinkTracker] Found 0 links in HTML` - HTML parsing issue
- `[LinkTracker] Skipping own domain link` - domain detection issue
- `[SendSmtpEmailJob] HTML changed: false` - modification not happening

Share the full log output for further investigation.

---

## Files Modified

1. `services/api/app/controllers/dashboard/dashboard_controller.rb`
   - Line 34-35: Use EmailOpen/EmailClick instead of TrackingEvent

2. `services/api/app/services/link_tracker.rb`
   - Lines 22-62: Added debug logging throughout track_links()

3. `services/api/app/jobs/send_smtp_email_job.rb`
   - Lines 56-75: Added debug logging for HTML transformation

---

## Commit

Commit: `2ac3590`
Branch: `claude/project-analysis-errors-Awt4F`

---

## Questions?

If dashboard overview still shows 0 clicks after rebuild, check:
1. Browser cache - hard refresh (Ctrl+Shift+R)
2. Rails cache - restart API container

If HTML links still not replaced, share output from:
```bash
./check-tracking-debug.sh
```
