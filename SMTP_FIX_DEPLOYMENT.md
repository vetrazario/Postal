# SMTP Email Flow Fix - Deployment Guide

## 🔧 Problem Summary

The SMTP email flow from AMS → Haraka → API → Postal was failing with **450 error** because:

1. **Wrong API endpoint**: SMTP Relay was sending to `/api/v1/emails/receive` but routes defined `/api/v1/smtp/receive`
2. **Payload format mismatch**: API controller expected different data structure than SMTP relay was sending
3. **Job processing mismatch**: Background job expected old format with `headers`, `body`, `tracking`

## ✅ Fixes Applied

### 1. SMTP Relay Endpoint Fix
**File**: `services/smtp-relay/server.js`
**Line 123**: Changed endpoint URL
```javascript
// BEFORE:
const response = await axios.post(`${API_URL}/api/v1/emails/receive`, payload, {

// AFTER:
const response = await axios.post(`${API_URL}/api/v1/smtp/receive`, payload, {
```

### 2. API Controller Payload Fix
**File**: `services/api/app/controllers/api/v1/smtp_controller.rb`

Updated to accept the correct payload format from server.js:
```ruby
# Now expects:
{
  envelope: { from: "...", to: [...] },
  message: { from: "...", to: "...", subject: "...", text: "...", html: "...", headers: {...} },
  raw: "base64..."
}
```

Added logging for debugging:
```ruby
Rails.logger.info "SMTP receive payload: #{params.to_unsafe_h.inspect}"
```

### 3. Background Job Fix
**File**: `services/api/app/jobs/send_smtp_email_job.rb`

Updated to process the new payload format:
```ruby
# Now reads:
envelope = email_data['envelope']
message = email_data['message']
raw = email_data['raw']

# And builds Postal payload from message structure
postal_payload = {
  to: Array(envelope[:to]),
  from: envelope[:from],
  subject: message[:subject],
  plain_body: message[:text],
  html_body: message[:html],
  ...
}
```

## 🚀 Deployment Instructions

### On the Server (linenarrow.com)

```bash
cd /opt/email-sender

# Run the deployment script
bash deploy-smtp-fix.sh
```

This script will:
1. Pull latest changes from `claude/setup-email-testing-YifKd` branch
2. Rebuild `smtp-relay` container (new endpoint URL)
3. Rebuild `api` container (new controller + job logic)
4. Restart `smtp-relay`, `api`, and `sidekiq` services
5. Show service status

### Expected Output

```
========================================
Deploying SMTP Relay Fix
========================================
This will:
  1. Fix SMTP endpoint URL in relay
  2. Fix payload format in API controller
  3. Fix background job processing
========================================

→ Pulling latest changes...
→ Rebuilding smtp-relay container...
→ Rebuilding api container...
→ Restarting services...
→ Waiting for services to start...
→ Checking service status...

✓ Deployment complete!
```

## 🧪 Testing

### 1. Test from AMS

Configure SMTP settings:
```
Host: linenarrow.com
Port: 2587
TLS/STARTTLS: Yes
Username: [from Dashboard → SMTP Credentials]
Password: [from Dashboard → SMTP Credentials]
```

Send test email from AMS.

### 2. Monitor Logs

**SMTP Relay logs** (should show 200 OK from API):
```bash
docker compose logs smtp-relay -f
```

Expected:
```
[session-id] Receiving message data...
[session-id] Parsed email:
  From: sender@example.com
  To: recipient@example.com
  Subject: Test Email
API response: 202 { status: 'queued', message_id: 'smtp_...', ... }
[session-id] Message forwarded successfully
```

**API logs** (should show controller receiving request):
```bash
docker compose logs api -f
```

Expected:
```
SMTP receive payload: {"envelope"=>{"from"=>"...", "to"=>[...]}, "message"=>{...}}
```

**Sidekiq logs** (should show job processing):
```bash
docker compose logs sidekiq -f
```

Expected:
```
SendSmtpEmailJob: Processing email...
SMTP email sent successfully: smtp_xxxxxxxxxxxx
```

**Monitor all together**:
```bash
docker compose logs smtp-relay api sidekiq -f
```

### 3. Check Dashboard

Go to `http://linenarrow.com/dashboard/logs`

You should see:
- New email log entry
- Status: `queued` → `processing` → `sent`
- Message ID: `smtp_xxxxxxxxxxxx`

## 📊 Email Flow Diagram

```
AMS Enterprise
    ↓ SMTP (port 2587)
SMTP Relay (Haraka)
    ↓ HTTP POST /api/v1/smtp/receive
Rails API Controller
    ↓ Create EmailLog (status: queued)
    ↓ Queue SendSmtpEmailJob
Sidekiq Background Job
    ↓ Extract message data
    ↓ Build Postal payload
Postal Client
    ↓ POST /api/v1/send/message
Postal Server
    ↓ SMTP (port 25)
External Mail Server
    ↓
Recipient Inbox ✓
```

## 🔍 Troubleshooting

### Still getting 404 errors
**Check containers were rebuilt:**
```bash
docker compose ps
docker compose logs smtp-relay --tail=50 | grep "api/v1/smtp"
```

Should see `/api/v1/smtp/receive`, NOT `/api/v1/emails/receive`

**If still wrong endpoint**, rebuild manually:
```bash
git pull origin claude/setup-email-testing-YifKd
docker compose build --no-cache smtp-relay
docker compose up -d smtp-relay
```

### Getting 400 Bad Request
**Check payload format:**
```bash
docker compose logs api --tail=100 | grep "SMTP receive payload"
```

Should show `envelope` and `message` keys.

### Job failing in Sidekiq
**Check Sidekiq logs:**
```bash
docker compose logs sidekiq --tail=100
```

Look for errors in `SendSmtpEmailJob`.

**Check Postal API key is set:**
```bash
docker compose exec api env | grep POSTAL_API_KEY
```

Should show: `POSTAL_API_KEY=FSJbztugA0ZmzAiF6GWWOtnv`

### Email stuck in 'queued' status
**Check Sidekiq is running:**
```bash
docker compose ps sidekiq
```

Should be `Up` and `healthy`.

**Check Redis connection:**
```bash
docker compose exec api rails console
> Sidekiq::Queue.new('mailers').size
```

Should show number of queued jobs.

## 📝 Changes Summary

| File | Change | Why |
|------|--------|-----|
| `services/smtp-relay/server.js` | Line 123: endpoint URL | Fix 404 error |
| `services/api/app/controllers/api/v1/smtp_controller.rb` | Accept `envelope` + `message` format | Match relay payload |
| `services/api/app/jobs/send_smtp_email_job.rb` | Process new data structure | Fix job processing |

## ✅ Success Criteria

After deployment, you should see:

1. ✅ AMS can connect to port 2587
2. ✅ SMTP Relay receives email
3. ✅ API responds 202 Accepted (not 404)
4. ✅ EmailLog created with status 'queued'
5. ✅ Sidekiq processes job
6. ✅ Email sent to Postal
7. ✅ Status updated to 'sent'
8. ✅ Recipient receives email

## 🆘 Need Help?

Check logs in this order:
```bash
# 1. SMTP Relay (did it receive from AMS?)
docker compose logs smtp-relay --tail=50

# 2. API (did controller accept request?)
docker compose logs api --tail=50

# 3. Sidekiq (did job process successfully?)
docker compose logs sidekiq --tail=50

# 4. Postal (did it send email?)
docker compose logs postal --tail=50
```

## 🎯 Next Steps After Deployment

1. Test email sending from AMS
2. Verify emails arrive at recipient inbox
3. Check bounce/delivery webhooks from Postal
4. Monitor Dashboard logs page
5. Set up SMTP credentials for production use
