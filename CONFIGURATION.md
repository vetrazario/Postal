# Web-Based Configuration System

This document describes the new web-based configuration management system that replaces hardcoded values and enables easy deployment to different servers.

## Overview

The system provides:
- **Web-based Settings Panel** - Configure all settings through Dashboard UI
- **Database Storage** - Settings stored in encrypted PostgreSQL database
- **Validation** - All settings validated before saving
- **Service Restart Tracking** - Automatic detection of which Docker services need restart
- **Connection Testing** - Test AMS and Postal connections before applying settings
- **Rake Tasks** - Command-line tools for configuration management
- **.env Synchronization** - Automatic sync between database and .env file

## Quick Start

### Initial Setup

1. **Run database migration:**
```bash
docker compose exec api rails db:migrate
```

2. **Load configuration from .env file:**
```bash
docker compose exec api rake config:load_from_env
```

3. **Access web panel:**
   - Go to: `https://your-domain.com/dashboard`
   - Login with credentials from .env (DASHBOARD_USERNAME, DASHBOARD_PASSWORD)
   - Navigate to Settings tab

## Web-Based Configuration Panel

### Accessing Settings

1. Login to Dashboard: `https://your-domain.com/dashboard`
2. Click on **Settings** in the navigation menu
3. You'll see 5 tabs:
   - **AI Analytics** - OpenRouter API configuration
   - **Server** - Domain and CORS settings
   - **AMS Integration** - AMS callback and API configuration
   - **Postal** - Postal mail server configuration
   - **Limits & Security** - Rate limits and security settings

### Configuration Tabs

#### Server Tab
- **Domain**: Your server domain (e.g., `send.example.com`)
  - Affects: API, Sidekiq, Postal, SMTP
  - Used for: Message-ID generation, email headers, tracking links
- **Allowed Sender Domains**: Comma-separated list of domains allowed in From addresses
  - Example: `example.com,mail.example.com`
- **CORS Origins**: Comma-separated list of allowed CORS origins
  - Example: `https://ams.example.com,https://admin.example.com`

#### AMS Integration Tab
- **AMS Callback URL**: URL to send webhooks back to AMS
  - Example: `https://ams.example.com/api/webhooks/send_server`
  - Affects: API, Sidekiq
- **AMS API URL**: URL for AMS API (optional, for status updates)
  - Example: `https://ams.example.com/api`
  - Affects: Sidekiq
- **AMS API Key**: Authentication key for AMS API (optional)
  - Affects: Sidekiq
- **Test Connection Button**: Verifies AMS server is reachable

#### Postal Tab
- **Postal API URL**: URL for Postal mail server
  - Default: `http://postal:5000`
  - Affects: API, Sidekiq
- **Postal API Key**: API key for Postal authentication
  - Affects: API, Sidekiq
- **Postal Signing Key**: Signing key for webhook verification
  - Affects: API
- **Test Connection Button**: Verifies Postal server is reachable

#### Limits & Security Tab
- **Daily Email Limit**: Maximum emails per day (0 = unlimited)
  - Default: 50000
  - Affects: API
- **Sidekiq Concurrency**: Number of parallel Sidekiq threads
  - Recommended: 5-10
  - Warning: High values require more memory
  - Affects: Sidekiq
- **Webhook Secret**: Secret key for signing outgoing webhooks (HMAC-SHA256)
  - Generate with: `openssl rand -hex 32`
  - Affects: API

### Applying Changes

1. Make changes in any tab and click **Save Configuration**
2. If changes affect running services, you'll see a **yellow warning banner**:
   - Lists which services need restart (api, sidekiq, postal)
   - Click **Apply Changes & Restart Services** button
3. Confirm restart (brief downtime warning)
4. Services will restart automatically with new configuration

### Security Features

- All sensitive data (API keys, secrets) encrypted in database using Rails encryption
- Password fields show dots, actual values hidden
- Test connection buttons verify settings before applying
- Validation prevents invalid domain names or URLs
- CSRF protection on all forms

## Rake Tasks

### View Current Configuration

```bash
docker compose exec api rake config:show
```

Shows all current SystemConfig values with masked sensitive data.

### Load Configuration from .env

```bash
docker compose exec api rake config:load_from_env
```

Loads configuration from .env file into SystemConfig database.
Useful for:
- Initial setup
- Restoring configuration from backup
- Migrating from old .env-based setup

### Export Configuration to .env

```bash
docker compose exec api rake config:sync_to_env
```

Exports SystemConfig database values to .env file.
Useful for:
- Creating backup of current configuration
- Preparing .env for Docker restart
- Synchronizing configuration across environments

### Generate postal.yml

```bash
docker compose exec api rake config:generate_postal_config
```

Generates `config/postal.yml` from template using environment variables.
Template: `config/postal.yml.template`
Output: `config/postal.yml`

### Test Connections

```bash
# Test AMS connection
docker compose exec api rake config:test_ams

# Test Postal connection
docker compose exec api rake config:test_postal
```

Tests HTTP connectivity to external services.

## Migration from Old System

If you're upgrading from hardcoded values:

1. **Backup your current .env file:**
```bash
cp .env .env.backup
```

2. **Run the migration:**
```bash
docker compose exec api rails db:migrate
```

3. **Load configuration from .env:**
```bash
docker compose exec api rake config:load_from_env
```

4. **Verify configuration:**
```bash
docker compose exec api rake config:show
```

5. **Access web panel to make further changes**

## Architecture

### Database Schema

Table: `system_configs` (singleton, only ID=1 exists)

Encrypted fields:
- `ams_api_key_encrypted`
- `postal_api_key_encrypted`
- `postal_signing_key_encrypted`
- `webhook_secret_encrypted`

Metadata fields:
- `restart_required` (boolean) - Whether services need restart
- `restart_services` (array) - List of services needing restart
- `changed_fields` (jsonb) - Fields that were changed

### Service Impact Mapping

Changes to these fields affect which services:

| Field | Affects Services |
|-------|-----------------|
| domain | api, sidekiq, postal |
| allowed_sender_domains | api |
| cors_origins | api |
| ams_callback_url | api, sidekiq |
| ams_api_key | sidekiq |
| ams_api_url | sidekiq |
| postal_api_url | api, sidekiq |
| postal_api_key | api, sidekiq |
| postal_signing_key | api |
| daily_limit | api |
| sidekiq_concurrency | sidekiq |
| webhook_secret | api |

### Code Integration

Services access configuration via:

```ruby
# Get domain value
SystemConfig.get(:domain)

# Get postal API URL
SystemConfig.get(:postal_api_url)

# Get full config instance
config = SystemConfig.instance
config.domain # => "send.example.com"
config.daily_limit # => 50000
```

## Troubleshooting

### Configuration not loading

```bash
# Check if SystemConfig exists
docker compose exec api rails console
> SystemConfig.instance

# Reload from .env if needed
docker compose exec api rake config:load_from_env
```

### Services not using new configuration

1. Check if restart is required:
```bash
docker compose exec api rake config:show
```

2. If restart required, use web panel's "Apply Changes" button, or:
```bash
docker compose restart api sidekiq postal
```

### Connection tests failing

1. Verify URLs are accessible from Docker network:
```bash
docker compose exec api curl -I https://your-ams-url
docker compose exec api curl -I http://postal:5000
```

2. Check firewall rules
3. Verify API keys are correct
4. Check DNS resolution

### Lost access to Dashboard

Configuration is stored in database, so if you lose .env:

1. Reset database and reload from backup .env:
```bash
docker compose exec api rails db:drop db:create db:migrate
docker compose exec api rake config:load_from_env
```

## Security Recommendations

1. **Encryption Keys**: Keep `ENCRYPTION_PRIMARY_KEY` and related keys secure
2. **Webhook Secret**: Use strong random values (32+ hex characters)
3. **API Keys**: Rotate periodically
4. **Dashboard Access**: Use strong DASHBOARD_PASSWORD
5. **Backups**: Regularly backup .env and database
6. **HTTPS**: Always use HTTPS in production
7. **Firewall**: Limit access to Dashboard to trusted IPs

## Files Reference

### Configuration Files
- `config/postal.yml.template` - Template for Postal configuration
- `env.example.txt` - Example .env file with all variables
- `.env` - Actual environment variables (git-ignored)
- `config/postal.yml` - Generated Postal configuration (git-ignored)

### Code Files
- `services/api/app/models/system_config.rb` - SystemConfig model
- `services/api/app/controllers/dashboard/settings_controller.rb` - Settings controller
- `services/api/app/views/dashboard/settings/` - View templates
- `services/api/lib/tasks/config.rake` - Rake tasks
- `services/api/config/initializers/system_config.rb` - Startup initializer
- `services/api/db/migrate/016_create_system_configs.rb` - Database migration

### Updated Files
- `docker-compose.yml` - Added AMS_API_URL to api and sidekiq
- `services/api/app/services/postal_client.rb` - Uses SystemConfig.get(:domain)
- `services/api/app/lib/message_id_generator.rb` - Uses SystemConfig.get(:domain)
- `services/api/app/jobs/build_email_job.rb` - Uses SystemConfig.get(:domain)
- `services/api/app/controllers/dashboard/smtp_credentials_controller.rb` - Uses SystemConfig.get(:domain)
- `services/api/app/services/ai/openrouter_client.rb` - Uses SystemConfig.get(:domain)

## Support

For issues or questions:
1. Check this documentation
2. Review logs: `docker compose logs -f api sidekiq`
3. Use rake tasks for diagnostics: `rake config:show`
4. Report issues on GitHub
