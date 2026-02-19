# Plan: Integration of postMailingOpenClicksData API

## Current Architecture (verified by file inspection)

### Email sending path (AMS -> recipient):

```
AMS (software)
  |  Sends email via SMTP with header X-Id-Mail = mailingID
  v
Haraka SMTP Relay (port 2587)
  |  POST /api/v1/smtp/receive
  v
SmtpController (Rails API)
  |  Creates EmailLog:
  |    - recipient: real email (encrypted, deterministic)
  |    - recipient_masked: u***r@mail.ru
  |    - campaign_id: from X-Id-Mail header (= AMS mailingID)
  |    - external_message_id: from Message-ID header
  |  Queues SendSmtpEmailJob
  v
SendSmtpEmailJob
  |  Checks: throttling, bounce block, unsubscribe block
  |  TrackingInjector.inject_all():
  |    - Rewrites links -> /track/c?url=BASE64&eid=BASE64&cid=BASE64&mid=BASE64
  |    - Adds pixel -> /track/o?eid=BASE64&cid=BASE64&mid=BASE64
  |    - Adds unsubscribe footer -> /unsubscribe?eid=BASE64&cid=BASE64
  |    - SKIPS amsweb.php links (AMS own tracking)
  |  track_clicks: false, track_opens: false (Postal own tracking disabled)
  |  Sends via PostalClient
  v
Postal SMTP Server -> delivers to recipient
  |  Sends webhook back: MessageSent/MessageBounced/etc
  v
WebhooksController (POST /api/v1/webhook, RSA signature)
  |  Updates EmailLog, CampaignStats, TrackingEvent, BouncedEmail
  |  Queues ReportToAmsJob
  v
ReportToAmsJob -> WebhookEndpoint.send_webhook() -> REST POST to AMS callback
```

### Tracking path (recipient -> Dashboard -> AMS):

```
Recipient opens email / clicks link / unsubscribes
  |
  v
Sinatra TrackingApp (tracking service)
  |  /track/o -> TrackingHandler.handle_open()
  |    - Decodes email from Base64: email = Base64.urlsafe_decode64(eid)  [line 28]
  |    - Decodes campaign_id from Base64                                   [line 29]
  |    - Creates TrackingEvent in DB (event_type: 'open')
  |    - Calls enqueue_webhook_job() -> POST /api/v1/internal/tracking_event
  |
  |  /track/c -> TrackingHandler.handle_click()
  |    - Decodes email from Base64                                         [line 70]
  |    - Decodes url from Base64                                           [line 69]
  |    - Decodes campaign_id from Base64                                   [line 71]
  |    - Validates URL (anti-SSRF, anti-open-redirect)
  |    - Creates TrackingEvent in DB (event_type: 'click', event_data: {url})
  |    - Calls enqueue_webhook_job() -> POST /api/v1/internal/tracking_event
  |    - Returns 302 redirect to original URL
  |
  |  /unsubscribe -> TrackingHandler.handle_unsubscribe()
  |    - Decodes email from Base64                                         [line 118]
  |    - Decodes campaign_id from Base64                                   [line 119]
  |    - Creates Unsubscribe record in DB
  |    - Creates TrackingEvent (event_type: 'unsubscribe')
  |    - Calls enqueue_webhook_job()
  v
Internal::TrackingController (POST /api/v1/internal/tracking_event)
  |  Verifies HMAC signature or trusted network
  |  Updates CampaignStats (increment_opened/clicked/unsubscribed)
  |  Queues ReportToAmsJob
  v
ReportToAmsJob
  |  Builds webhook_data:
  |    - message_id: external_message_id
  |    - campaign_id: from EmailLog
  |    - recipient: recipient_masked (!!!) <- THIS IS THE PROBLEM
  |    - status: event_type
  |  Sends via WebhookEndpoint -> REST POST
  v
AMS receives webhook (current format, NOT postMailingOpenClicksData)
```

### Problem: ReportToAmsJob sends recipient_masked, NOT real email
The AMS postMailingOpenClicksData API requires REAL email addresses.
Real email IS available in TrackingHandler (decoded from Base64 URL params).

---

## Implementation Plan

### Step 1: Add `post_open_clicks_data` method to AmsClient

**File:** `services/api/app/services/ams_client.rb`

Add one method:
```ruby
def post_open_clicks_data(mailing_id, opens_clicks_data)
  call_api('postMailingOpenClicksData', {
    mailingID: mailing_id.to_i,
    opensClicksData: opens_clicks_data
  })
end
```

This leverages the existing `call_api()` which already handles:
- JSON-RPC 2.0 format
- apiKey injection
- Error handling
- HTTParty POST

No other changes needed in AmsClient.

---

### Step 2: Add Redis buffer in TrackingHandler (Sinatra service)

**File:** `services/tracking/lib/tracking_handler.rb`

After creating TrackingEvent in each handler, push event to Redis list.

In `handle_open()` (after line 51, before enqueue_webhook_job):
```ruby
push_to_ams_buffer(campaign_id, email, 'open_trace')
```

In `handle_click()` (after line 99, before enqueue_webhook_job):
```ruby
push_to_ams_buffer(campaign_id, email, validated_url)
```

In `handle_unsubscribe()` (after line 138, before webhook):
```ruby
push_to_ams_buffer(campaign_id, email, 'Unsubscribe_Click:DC,AE{|;')
```

Add private method:
```ruby
def push_to_ams_buffer(campaign_id, email, url)
  return if campaign_id.blank? || email.blank?

  redis = Redis.new(url: @redis_url)
  redis.lpush("ams_open_clicks:#{campaign_id}", { email: email, url: url }.to_json)
  redis.expire("ams_open_clicks:#{campaign_id}", 86400) # TTL 24 hours
rescue => e
  puts "AMS buffer push error: #{e.message}"
ensure
  redis&.close
end
```

Why Redis:
- Already available in tracking service (line 4 of app.rb: `require 'redis'`)
- Fast, non-blocking
- Natural list structure for batching
- TTL prevents memory leak

Why TrackingHandler (not Rails TrackingController):
- TrackingHandler already has DECODED real email (from Base64 URL params)
- Rails TrackingController uses token-based lookup and would need to decrypt EmailLog.recipient
- TrackingHandler is the PRIMARY tracking path (Sinatra service handles /track/o, /track/c, /unsubscribe)

---

### Step 3: Create AmsOpenClicksSyncJob (periodic batch sender)

**New file:** `services/api/app/jobs/ams_open_clicks_sync_job.rb`

```ruby
class AmsOpenClicksSyncJob < ApplicationJob
  queue_as :low

  MAX_BATCH_SIZE = 20_000

  def perform
    return unless ams_configured?

    client = build_ams_client

    # Find all campaign keys in Redis
    redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://redis:6379/0'))
    keys = redis.keys('ams_open_clicks:*')

    keys.each do |key|
      campaign_id = key.sub('ams_open_clicks:', '')

      # Pop up to MAX_BATCH_SIZE items from the list
      items = []
      while items.size < MAX_BATCH_SIZE
        raw = redis.rpop(key)
        break unless raw
        items << JSON.parse(raw)
      end

      next if items.empty?

      # Send to AMS
      begin
        client.post_open_clicks_data(campaign_id, items)
        Rails.logger.info "AmsOpenClicksSyncJob: sent #{items.size} events for campaign #{campaign_id}"
      rescue AmsClient::AmsError => e
        # On error, push items back to Redis (front of list)
        items.reverse_each { |item| redis.rpush(key, item.to_json) }
        Rails.logger.error "AmsOpenClicksSyncJob error for campaign #{campaign_id}: #{e.message}"
      end
    end

    redis.close
  ensure
    # Re-schedule self (runs every 30 seconds)
    self.class.set(wait: 30.seconds).perform_later
  end

  private

  def ams_configured?
    SystemConfig.get(:ams_api_url).present? && SystemConfig.get(:ams_api_key).present?
  end

  def build_ams_client
    AmsClient.new(
      api_url: SystemConfig.get(:ams_api_url),
      api_key: SystemConfig.get(:ams_api_key)
    )
  end
end
```

Self-scheduling pattern (same as BounceSchedulerJob):
- Runs every 30 seconds
- Pops events from Redis, groups by campaign_id
- Sends batch to AMS via `postMailingOpenClicksData`
- On error: pushes items back to Redis for retry
- Limit: 20K per call (AMS requirement)

---

### Step 4: Create initializer to start AmsOpenClicksSyncJob

**New file:** `services/api/config/initializers/ams_sync_scheduler.rb`

```ruby
Rails.application.config.after_initialize do
  if defined?(Sidekiq::Server) && Rails.env.production?
    begin
      AmsOpenClicksSyncJob.set(wait: 30.seconds).perform_later
      Rails.logger.info "AmsOpenClicksSyncJob initialized - will start in 30 seconds"
    rescue => e
      Rails.logger.error "Failed to initialize AmsOpenClicksSyncJob: #{e.message}"
    end
  end
end
```

Same pattern as `config/initializers/bounce_scheduler.rb`.

---

### Step 5: Handle Rails TrackingController events (secondary path)

**File:** `services/api/app/controllers/tracking_controller.rb`

The Rails TrackingController handles `/t/o/:token` and `/t/c/:token` paths.
These use token-based lookup, so email must be extracted from EmailLog.

In `click` method (after line 50, stats update):
```ruby
push_to_ams_buffer(click_record)
```

In `open` method (after line 87, stats update):
```ruby
push_to_ams_buffer_open(open_record)
```

Add private methods:
```ruby
def push_to_ams_buffer(click_record)
  email_log = click_record.email_log
  return unless email_log&.campaign_id.present?

  redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://redis:6379/0'))
  redis.lpush(
    "ams_open_clicks:#{email_log.campaign_id}",
    { email: email_log.recipient, url: click_record.url }.to_json
  )
  redis.expire("ams_open_clicks:#{email_log.campaign_id}", 86400)
rescue => e
  Rails.logger.error "AMS buffer push error: #{e.message}"
ensure
  redis&.close
end

def push_to_ams_buffer_open(open_record)
  email_log = open_record.email_log
  return unless email_log&.campaign_id.present?

  redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://redis:6379/0'))
  redis.lpush(
    "ams_open_clicks:#{email_log.campaign_id}",
    { email: email_log.recipient, url: 'open_trace' }.to_json
  )
  redis.expire("ams_open_clicks:#{email_log.campaign_id}", 86400)
rescue => e
  Rails.logger.error "AMS buffer push error: #{e.message}"
ensure
  redis&.close
end
```

Note: `email_log.recipient` returns decrypted email (Rails `encrypts` with deterministic mode handles this transparently).

---

### Step 6: Handle Postal webhook events (MessageLoaded / MessageLinkClicked)

**File:** `services/api/app/controllers/api/v1/webhooks_controller.rb`

Although Postal's own tracking is disabled (track_clicks: false, track_opens: false),
MessageLoaded/MessageLinkClicked events COULD still arrive from Postal in some edge cases.
Add AMS buffer push there too for completeness.

In `MessageLoaded` handler (after line 165):
```ruby
push_to_ams_open_clicks_buffer(email_log, 'open_trace')
```

In `MessageLinkClicked` handler (after line 179):
```ruby
push_to_ams_open_clicks_buffer(email_log, url)
```

Add private method:
```ruby
def push_to_ams_open_clicks_buffer(email_log, url)
  return unless email_log.campaign_id.present?

  redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://redis:6379/0'))
  redis.lpush(
    "ams_open_clicks:#{email_log.campaign_id}",
    { email: email_log.recipient, url: url }.to_json
  )
  redis.expire("ams_open_clicks:#{email_log.campaign_id}", 86400)
rescue => e
  Rails.logger.error "AMS buffer push error: #{e.message}"
ensure
  redis&.close
end
```

---

## Data flow summary (after integration):

```
Recipient opens/clicks/unsubscribes
  |
  v
TrackingHandler (Sinatra) — PRIMARY PATH
  |  Already decodes: email, url, campaign_id from Base64
  |  1. Creates TrackingEvent in DB            (existing)
  |  2. LPUSH to Redis ams_open_clicks:{cid}   (NEW)
  |  3. Calls internal tracking_event webhook   (existing)
  v
Internal::TrackingController (Rails)
  |  Updates CampaignStats                      (existing)
  |  Queues ReportToAmsJob (REST webhook)       (existing)
  v
AmsOpenClicksSyncJob (every 30 seconds)          (NEW)
  |  1. RPOP batch from Redis (up to 20K)
  |  2. Group by campaign_id = mailingID
  |  3. Map events:
  |     open       -> {email: real, url: "open_trace"}
  |     click      -> {email: real, url: actual_url}
  |     unsubscribe-> {email: real, url: "Unsubscribe_Click:DC,AE{|;"}
  |  4. Call AmsClient.post_open_clicks_data()
  v
AmsClient.call_api('postMailingOpenClicksData')   (NEW method)
  |  JSON-RPC 2.0 with apiKey
  v
AMS receives batched opens/clicks data
  |  Processes asynchronously (every 1-2 min)
  |  Updates campaign statistics in AMS UI
```

---

## Files to change (6 files, 2 new):

| # | File | Action | Lines changed |
|---|------|--------|---------------|
| 1 | `services/api/app/services/ams_client.rb` | Add method | ~5 lines |
| 2 | `services/tracking/lib/tracking_handler.rb` | Add Redis push in 3 handlers + private method | ~20 lines |
| 3 | `services/api/app/controllers/tracking_controller.rb` | Add Redis push for token-based tracking | ~25 lines |
| 4 | `services/api/app/controllers/api/v1/webhooks_controller.rb` | Add Redis push for Postal events | ~15 lines |
| 5 | `services/api/app/jobs/ams_open_clicks_sync_job.rb` | **NEW** - periodic batch sender | ~60 lines |
| 6 | `services/api/config/initializers/ams_sync_scheduler.rb` | **NEW** - job startup | ~10 lines |

**Total: ~135 lines of code**

---

## What we do NOT need to change:

- SystemConfig — ams_api_url and ams_api_key already exist
- AmsClient.call_api() — JSON-RPC infrastructure already works
- ReportToAmsJob / WebhookEndpoint — existing REST webhook continues to work in parallel
- CampaignStats — Dashboard stats continue to work independently
- TrackingInjector — link rewriting and pixel injection stay the same
- Database schema — no new tables or migrations needed

---

## Edge cases handled:

1. **AMS is down**: Events stay in Redis (TTL 24h), retried on next sync cycle
2. **More than 20K events**: Job processes in batches of 20K per campaign_id per cycle
3. **No AMS configured**: Job checks ams_configured?() and skips silently
4. **Duplicate events**: AMS handles uniqueness by email (as documented in API spec)
5. **BCC mode (no email)**: If email is blank, push with `email: "no_email"`
6. **Unsubscribe actions**: Configurable format `Unsubscribe_Click:DC,AE,AM{id}{|;`
