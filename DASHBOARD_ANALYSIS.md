# Dashboard Analysis and Improvement Proposals

## Current Dashboard Structure

### Controllers (12 total)
| Controller | Path | Purpose |
|------------|------|---------|
| `DashboardController` | `/dashboard` | Main overview, stats, health checks |
| `SettingsController` | `/dashboard/settings` | System configuration (5 tabs) |
| `ApiKeysController` | `/dashboard/api_keys` | API key management |
| `SmtpCredentialsController` | `/dashboard/smtp_credentials` | SMTP auth credentials |
| `WebhooksController` | `/dashboard/webhooks` | Webhook endpoints |
| `TemplatesController` | `/dashboard/templates` | Email templates |
| `LogsController` | `/dashboard/logs` | Email logs |
| `AnalyticsController` | `/dashboard/analytics` | Statistics & charts |
| `AiAnalyticsController` | `/dashboard/ai_analytics` | AI-powered analysis |
| `MailingRulesController` | `/dashboard/mailing_rules` | Email routing rules |
| `ErrorMonitorController` | `/dashboard/error_monitor` | Error tracking |
| `BaseController` | - | Base controller with auth |

### Settings Tabs
1. **AI Analytics** - OpenRouter API key, model, temperature, max_tokens
2. **Server** - domain, allowed_sender_domains, cors_origins
3. **AMS Integration** - ams_callback_url, ams_api_url, ams_api_key
4. **Postal** - postal_api_url, postal_api_key, postal_signing_key
5. **Limits & Security** - daily_limit, sidekiq_concurrency, webhook_secret, smtp_relay_secret

---

## Configuration Analysis

### Currently Configurable from Dashboard

#### Via Settings > SystemConfig:
| Field | Tab | Services Affected |
|-------|-----|-------------------|
| `domain` | Server | API, Sidekiq, Postal |
| `allowed_sender_domains` | Server | API |
| `cors_origins` | Server | API |
| `ams_callback_url` | AMS | API, Sidekiq |
| `ams_api_url` | AMS | Sidekiq |
| `ams_api_key` | AMS | Sidekiq |
| `postal_api_url` | Postal | API, Sidekiq |
| `postal_api_key` | Postal | API, Sidekiq |
| `postal_signing_key` | Postal | API |
| `daily_limit` | Limits | API |
| `sidekiq_concurrency` | Limits | Sidekiq |
| `webhook_secret` | Limits | API |
| `smtp_relay_secret` | Limits | SMTP Relay, API |

#### Via SMTP Credentials Page:
- Username (auto-generated: `smtp_xxxxx`)
- Password (auto-generated, shown once)
- Description
- Rate limit
- Active/Inactive status

#### Via API Keys Page:
- API key (auto-generated)
- Name
- Permissions
- Rate limit
- Daily limit

#### Via AI Settings:
- OpenRouter API key
- AI model selection
- Temperature
- Max tokens
- Enable/disable AI

---

### NOT Configurable from Dashboard

#### Must Stay in ENV (Security/Infrastructure):
| Variable | Reason |
|----------|--------|
| `POSTGRES_PASSWORD` | Database access - needed at container startup |
| `MARIADB_PASSWORD` | Postal database - needed at startup |
| `RABBITMQ_PASSWORD` | Message queue - needed at startup |
| `SECRET_KEY_BASE` | Rails master secret - needed before Rails loads |
| `ENCRYPTION_*` | Encryption keys - needed before Rails loads |
| `REDIS_URL` | Infrastructure connection string |
| `DASHBOARD_USERNAME/PASSWORD` | Needed for auth before DB access |

#### Should Be Added to Dashboard:
| Variable | Current Location | Proposed Tab |
|----------|------------------|--------------|
| `SIDEKIQ_WEB_USERNAME/PASSWORD` | ENV only | Limits & Security |
| `LOG_LEVEL` | ENV only | Server |
| `SENTRY_DSN` | ENV only | Server |
| `LETSENCRYPT_EMAIL` | ENV only | Server |
| `POSTAL_WEBHOOK_PUBLIC_KEY` | ENV only | Postal |
| `SMTP_RELAY_PORT` | SystemConfig (no UI) | Limits & Security |
| `SMTP_AUTH_REQUIRED` | SystemConfig (no UI) | Limits & Security |
| `SMTP_RELAY_TLS` | SystemConfig (no UI) | Limits & Security |

---

## Issues Found

### 1. Redundant SMTP Relay Configuration
**Problem:** SystemConfig has `smtp_relay_username` and `smtp_relay_password` fields, but SMTP authentication now uses the `SmtpCredential` model.

**Files affected:**
- `app/models/system_config.rb:80-82`
- `db/migrate/017_add_smtp_relay_to_system_configs.rb`

**Solution:** Remove redundant fields from SystemConfig. SmtpCredential model handles all SMTP auth.

### 2. Missing UI for SystemConfig SMTP Fields
**Problem:** These fields exist in model but have no UI:
- `smtp_relay_port` (default: 2587)
- `smtp_relay_auth_required` (default: true)
- `smtp_relay_tls_enabled` (default: true)

**File:** `app/views/dashboard/settings/_limits_config_form.html.erb`

### 3. Missing Postal Webhook Public Key
**Problem:** No way to configure `POSTAL_WEBHOOK_PUBLIC_KEY` from Dashboard for verifying incoming webhooks from Postal.

### 4. No Test Button for SMTP Relay
**Problem:** AMS and Postal have "Test Connection" buttons, but SMTP Relay doesn't (placeholder only).

---

## Improvement Proposals

### A. Priority 1: Missing Settings Fields

#### 1. Add SMTP Relay Settings to UI
Add to `_limits_config_form.html.erb`:
- SMTP Relay Port (number field, default 2587)
- Auth Required (checkbox)
- TLS Enabled (checkbox)
- Test Connection button

#### 2. Add Postal Webhook Public Key
Add to `_postal_config_form.html.erb`:
- Textarea for PEM public key
- Instructions for obtaining key from Postal

#### 3. Add Sidekiq Web Credentials
Add new section in Limits & Security:
- Sidekiq Web Username
- Sidekiq Web Password
- Enable/Disable toggle

#### 4. Add Logging Settings
Add to Server tab:
- Log Level dropdown (debug, info, warn, error)
- Sentry DSN (optional)

### B. Priority 2: Functionality Improvements

#### 5. Real Test for SMTP Relay
Implement actual SMTP connection test in `SmtpCredentialsController#test_connection`:
- Connect to smtp-relay container
- Authenticate with credential
- Return success/failure

#### 6. Password Regeneration for SMTP Credentials
Add "Regenerate Password" button for existing credentials.

#### 7. Configuration Backup/Restore
- Export settings to JSON
- Import settings from JSON
- Version history of configuration changes

#### 8. Audit Log
Track who changed what settings and when.

### C. Priority 3: New Features

#### 9. System Diagnostics Page
- Check all service health
- TLS certificate status
- DNS configuration check
- Disk/memory usage

#### 10. Email Queue Visualization
- Show pending emails by status
- Ability to retry/delete stuck emails

#### 11. Real-time Stats
WebSocket connection for live dashboard updates.

#### 12. Webhook Logs Improvements
- Detailed request/response viewing
- Retry specific webhook
- Filter by status

---

## Code Cleanup

### Remove Redundant Fields
Migration to remove from SystemConfig:
- `smtp_relay_username` (use SmtpCredential instead)
- `smtp_relay_password_encrypted` (use SmtpCredential instead)

These fields were added for SMTP Relay but are now handled by SmtpCredential model.

### Update FIELD_AFFECTS
Remove references to deprecated fields in `system_config.rb:192-193`.

---

## Implementation Priority

### Phase 1 (Critical)
- [ ] Add missing SMTP Relay fields to UI
- [ ] Add Postal Webhook Public Key field
- [ ] Implement real SMTP Relay test

### Phase 2 (Important)
- [ ] Add Sidekiq Web credentials
- [ ] Add Log Level setting
- [ ] Remove redundant SMTP fields
- [ ] Password regeneration for SMTP

### Phase 3 (Nice to Have)
- [ ] Configuration backup/restore
- [ ] Audit log
- [ ] System diagnostics
- [ ] Real-time updates

---

## Summary

**Current State:**
- Dashboard is functional with 12 controllers
- Most critical settings are configurable
- SMTP authentication properly uses SmtpCredential model
- Good separation between API Keys, SMTP Credentials, and System Config

**Gaps:**
- Some SystemConfig fields have no UI (SMTP port, TLS, auth required)
- No Postal webhook public key configuration
- Redundant SMTP relay fields in SystemConfig
- Some ENV-only variables could be in Dashboard

**Recommendation:**
Implement Phase 1 items first as they affect core functionality. The SMTP Relay settings in UI and Postal webhook key are important for proper security configuration.
