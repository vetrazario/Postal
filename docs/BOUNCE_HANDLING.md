# Bounce Handling Strategy

## Overview
The system implements a two-part bounce handling strategy:
1. **Stop mailing** - Trigger AMS stop for critical bounce categories
2. **Bounce list management** - Only add quality issues to bounce list

## Bounce Categories

### Add to Bounce List (Quality Issues)
These categories indicate problems with the email address itself:

| Category | Stop Mailing | Add to Bounce List | Description |
|-----------|--------------|-------------------|-------------|
| `user_not_found` | No | Yes | Email address does not exist |
| `spam_block` | Yes | Yes | Email marked as spam |
| `mailbox_full` | Yes | Yes | Mailbox is permanently full |
| `authentication` | No | Yes | SPF/DKIM/DMARC failure |

### Do NOT Add to Bounce List (Sender Issues)
These categories indicate problems with sending, not the recipient:

| Category | Stop Mailing | Add to Bounce List | Description |
|-----------|--------------|-------------------|-------------|
| `rate_limit` | Yes | No | Sending rate exceeded |
| `temporary` | Yes | No | Temporary server error |
| `connection` | Yes | No | Connection error |

## Critical Bounce Detection
The system automatically detects critical bounce categories and stops mailing:
- Rate limit errors
- Spam blocks
- Mailbox full issues
- Temporary errors
- Connection errors

Detection window: Last 5 minutes

## CSV Export Format
Bounce exports include a "Bounce Status" column:
- "Hard: Not Found" - Address is invalid
- "Hard: Mailbox Full" - Mailbox is full
- "Hard: Spam Block" - Marked as spam
- "Hard: Auth Fail" - Authentication failure
- "Rate Limited" - Rate limit exceeded
- "Temporary Error" - Temporary server error
- "Connection Error" - Connection failed

## API Endpoints

### Check Bounce Status
```
GET /api/v1/bounce_status/check?email=test@example.com&campaign_id=123
```

Response:
```json
{
  "email": "t***@example.com",
  "is_bounced": true,
  "is_unsubscribed": false,
  "campaign_id": "123",
  "blocked": true
}
```

### Webhook Endpoint
```
POST /api/v1/webhook
```

Receives webhooks from Postal with bounce information.

## Background Jobs

### CheckMailingThresholdsJob
- **Queue:** `critical`
- **Purpose:** Monitor thresholds and stop mailing
- **Triggers:** On every bounce event
- **Actions:**
  - Checks for critical bounce categories in last 5 minutes
  - Stops mailing via AMS if thresholds exceeded
  - Sends notifications

### MonitorBounceCategoriesJob
- **Queue:** `low`
- **Purpose:** Monitor bounce category rates
- **Triggers:** Manual or scheduled
- **Actions:**
  - Calculates bounce rates by category for last 24 hours
  - Sends alerts if thresholds exceeded
  - Thresholds:
    - `user_not_found`: 10%
    - `spam_block`: 5%
    - `mailbox_full`: 3%
    - `authentication`: 2%

### CleanupOldBouncesJob
- **Queue:** `low`
- **Purpose:** Clean up old bounce records
- **Triggers:** Scheduled daily
- **Actions:**
  - Deletes bounce records older than 90 days
  - Deletes unsubscribe records older than 90 days

### BounceSchedulerJob
- **Queue:** `low`
- **Purpose:** Schedule periodic bounce cleanup
- **Triggers:** Manual start, then self-schedules
- **Actions:**
  - Schedules `CleanupOldBouncesJob` daily
  - Self-reschedules for next day

## Models

### BouncedEmail
Stores bounce information with the following fields:
- `email` - Email address (encrypted)
- `bounce_type` - 'hard' or 'soft' (all are 'hard' now)
- `bounce_category` - Category from ErrorClassifier
- `smtp_code` - SMTP response code
- `smtp_message` - SMTP response message
- `campaign_id` - Campaign ID (null for global)
- `bounce_count` - Number of bounces
- `first_bounced_at` - First bounce timestamp
- `last_bounced_at` - Last bounce timestamp

### Methods
- `blocked?(email:, campaign_id:)` - Check if email is blocked
- `record_bounce_if_needed(...)` - Record bounce only if needed
- `status_description` - Get human-readable status for CSV

## ErrorClassifier

Classifies bounce errors into categories:

### Categories
- `user_not_found` - Email doesn't exist
- `spam_block` - Marked as spam
- `mailbox_full` - Mailbox is full
- `authentication` - SPF/DKIM/DMARC failure
- `rate_limit` - Rate limit exceeded
- `temporary` - Temporary error
- `connection` - Connection error
- `unknown` - Unknown error

### Constants
- `NON_BOUNCE_CATEGORIES` - Categories that don't go to bounce list
- `STOP_MAILING_CATEGORIES` - Categories that stop mailing

## Monitoring

### Bounce Category Monitoring
The system monitors bounce category rates and sends alerts when thresholds are exceeded:
- Email notifications to configured address
- AMS webhook notifications
- Dashboard alerts

### Health Checks
Health endpoint includes bounce table checks:
```
GET /api/v1/health
```

Response includes:
- Database connectivity
- Redis connectivity
- Postal connectivity
- Sidekiq status
- Bounce tables existence

## Best Practices

1. **Regular Cleanup** - Run `CleanupOldBouncesJob` daily to prevent table growth
2. **Monitor Rates** - Use `MonitorBounceCategoriesJob` to track bounce category rates
3. **Review Alerts** - Act on bounce category alerts promptly
4. **CSV Exports** - Regularly export bounce lists for analysis
5. **Test Bounce Handling** - Use test emails to verify bounce handling logic

## Troubleshooting

### Bounce not being recorded
- Check if category is in `NON_BOUNCE_CATEGORIES`
- Verify `should_add_to_bounce` is true in ErrorClassifier
- Check database logs for errors

### Mailing not stopping
- Verify `should_stop_mailing` is true in ErrorClassifier
- Check `CheckMailingThresholdsJob` logs
- Verify AMS API credentials are correct

### High bounce rates
- Review bounce category breakdown
- Check for authentication issues (SPF/DKIM/DMARC)
- Verify sender reputation
- Review email content for spam triggers


