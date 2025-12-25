# IMPLEMENTATION PLAN: Complete Email Sender with Dashboard

## 🎯 PROJECT GOAL

Build a production-ready email sending infrastructure that:
- Accepts SMTP connections from AMS Enterprise (Haraka on port 587)
- Parses and rebuilds emails to hide AMS traces
- Sends through Postal mail server
- Provides web dashboard for all configuration (no CLI needed)
- Includes AI-powered log analytics via OpenRouter

---

## ✅ PHASE 1: CRITICAL FIXES (COMPLETED)

### Completed Tasks:
- [x] Created `.env` with generated secrets
- [x] Generated `config/postal.yml` with real passwords
- [x] Created `config/htpasswd` for Nginx Basic Auth
- [x] Updated `nginx.conf` with Postal Web UI proxy
- [x] Committed configuration fixes

### Result:
Postal can now connect to MariaDB and RabbitMQ successfully.

---

## 🚀 PHASE 2: SMTP RELAY WITH HARAKA

### Architecture Overview:

```
AMS Enterprise (SMTP Client)
    ↓
Port 587 (TLS + AUTH)
    ↓
Haraka SMTP Server
    ↓
Parse MIME → Rebuild Headers → Extract Tracking
    ↓
HTTP POST to Rails API
    ↓
Sidekiq Job Queue
    ↓
Postal API
    ↓
Internet (via SMTP)
```

### 2.1 Create Haraka Service Structure

**Directory:** `services/smtp-relay/`

**Files to create:**
```
services/smtp-relay/
├── package.json
├── server.js
├── Dockerfile
├── config/
│   ├── smtp.ini
│   ├── plugins
│   ├── host_list
│   └── auth_flat_file.ini
├── plugins/
│   ├── auth.js                    # SMTP AUTH (PLAIN/LOGIN)
│   ├── parse_email.js             # MIME parser
│   ├── rebuild_headers.js         # Remove AMS traces
│   ├── inject_tracking.js         # Add tracking pixel & links
│   └── forward_to_api.js          # Send to Rails API
└── lib/
    ├── mime_parser.js             # MIME parsing utilities
    └── header_builder.js          # Build new headers
```

### 2.2 Haraka Configuration

**`config/smtp.ini`:**
```ini
[smtp]
port=587
address=0.0.0.0
nodes=cpus

[tls]
key=/etc/ssl/private/server.key
cert=/etc/ssl/certs/server.crt

[auth]
methods=PLAIN,LOGIN
```

**`config/plugins`:**
```
# Core plugins
tls
auth/flat_file
data.headers
data.uribl
record_envelope_addresses

# Custom plugins
auth
parse_email
rebuild_headers
inject_tracking
forward_to_api
```

### 2.3 SMTP Authentication Plugin

**`plugins/auth.js`:**
- Verify SMTP credentials against PostgreSQL `smtp_credentials` table
- Support PLAIN and LOGIN auth methods
- Hash passwords with bcrypt
- Log authentication attempts

### 2.4 MIME Parser Plugin

**`plugins/parse_email.js`:**
- Parse multipart/mixed, multipart/alternative
- Extract plain and HTML bodies
- Extract attachments (base64 decode)
- Preserve MIME structure

Key functions:
- `parseHeaders()` - Extract From, To, Subject, Message-ID
- `parseBody()` - Parse MIME parts
- `extractAttachments()` - Get files with content-type & encoding

### 2.5 Header Rebuilder Plugin

**`plugins/rebuild_headers.js`:**

Remove AMS traces:
- Delete all `Received:` headers
- Replace `Message-ID:` with new one: `<local_{random24hex}@linenarrow.com>`
- Remove `X-AMS-*` headers
- Remove `Return-Path:` (will be set by Postal)

Preserve required headers:
- `From:` (keep original)
- `To:`, `Cc:`, `Bcc:` (keep all)
- `Subject:` (keep)
- `Date:` (keep or regenerate)
- `MIME-Version:` (keep)
- `Content-Type:` (keep)

Add new headers:
- `Message-ID:` (generate new)
- `X-Mailer: Postal` (optional)

### 2.6 Tracking Injection Plugin

**`plugins/inject_tracking.js`:**

**Open tracking:**
- Add 1x1 transparent pixel before `</body>` tag
- URL format: `/track/o?eid={base64_email}&cid={campaign_id}&mid={message_id}`

**Click tracking:**
- Find all `<a href="URL">` in HTML
- Replace with: `/track/c?url={base64_url}&eid={base64_email}&cid={campaign_id}&mid={message_id}`
- Store original URLs in database

### 2.7 Forward to API Plugin

**`plugins/forward_to_api.js`:**

Send HTTP POST to Rails API:
```javascript
POST http://api:3000/api/v1/smtp/receive
Content-Type: application/json
Authorization: Bearer {SMTP_RELAY_API_KEY}

{
  "envelope": {
    "from": "sender@domain.com",
    "to": ["recipient@example.com"]
  },
  "headers": {
    "from": "Sender Name <sender@domain.com>",
    "to": "Recipient <recipient@example.com>",
    "subject": "Email Subject",
    "message_id": "<local_abc123@linenarrow.com>",
    "date": "Wed, 25 Dec 2024 10:00:00 +0000"
  },
  "body": {
    "plain": "Plain text version...",
    "html": "<html>HTML version with tracking...</html>"
  },
  "attachments": [
    {
      "filename": "document.pdf",
      "content_type": "application/pdf",
      "data": "base64_encoded_content..."
    }
  ],
  "tracking": {
    "campaign_id": "extracted_from_headers",
    "affiliate_id": "extracted_from_headers"
  }
}
```

### 2.8 Add to docker-compose.yml

```yaml
smtp-relay:
  build:
    context: ./services/smtp-relay
    dockerfile: Dockerfile
  container_name: email_smtp_relay
  restart: unless-stopped
  ports:
    - "587:587"
  environment:
    - SMTP_PORT=587
    - TLS_ENABLED=true
    - API_URL=http://api:3000
    - API_KEY=${SMTP_RELAY_API_KEY}
    - POSTGRES_URL=postgres://email_sender:${POSTGRES_PASSWORD}@postgres:5432/email_sender
  volumes:
    - ./services/smtp-relay/config:/app/config
    - smtp_relay_logs:/app/logs
  deploy:
    resources:
      limits:
        memory: 300M
      reservations:
        memory: 150M
  healthcheck:
    test: ["CMD", "nc", "-z", "localhost", "587"]
    interval: 30s
    timeout: 10s
    retries: 3
  networks:
    - frontend
    - backend
  depends_on:
    - postgres
    - api

volumes:
  smtp_relay_logs:
```

---

## 📊 PHASE 3: DASHBOARD ENHANCEMENTS

### 3.1 Database Migrations

Create new tables:

**006_create_smtp_credentials.rb:**
```ruby
create_table :smtp_credentials do |t|
  t.string :username, null: false
  t.string :password_hash, null: false  # bcrypt
  t.string :description
  t.boolean :active, default: true
  t.integer :rate_limit, default: 100  # emails per hour
  t.datetime :last_used_at
  t.timestamps
end

add_index :smtp_credentials, :username, unique: true
```

**007_create_webhook_endpoints.rb:**
```ruby
create_table :webhook_endpoints do |t|
  t.string :url, null: false
  t.string :secret_key
  t.boolean :active, default: true
  t.json :events, default: ['delivered', 'opened', 'clicked', 'bounced', 'failed', 'complained']
  t.integer :retry_count, default: 3
  t.integer :timeout, default: 30
  t.timestamps
end
```

**008_create_webhook_logs.rb:**
```ruby
create_table :webhook_logs do |t|
  t.references :webhook_endpoint, null: false, foreign_key: true
  t.string :event_type
  t.string :message_id
  t.integer :response_code
  t.text :response_body
  t.boolean :success
  t.datetime :delivered_at
  t.timestamps
end

add_index :webhook_logs, :message_id
add_index :webhook_logs, :event_type
add_index :webhook_logs, :created_at
```

**009_create_ai_settings.rb:**
```ruby
create_table :ai_settings, id: false do |t|
  t.primary_key :id, default: 1  # Singleton
  t.string :openrouter_api_key_encrypted
  t.string :model_name, default: 'anthropic/claude-3.5-sonnet'
  t.float :temperature, default: 0.7
  t.integer :max_tokens, default: 4000
  t.boolean :enabled, default: false
  t.timestamps
end
```

**010_create_ai_analyses.rb:**
```ruby
create_table :ai_analyses do |t|
  t.string :analysis_type  # bounce_analysis, time_optimization, campaign_comparison
  t.datetime :period_start
  t.datetime :period_end
  t.text :prompt
  t.text :result
  t.json :metadata
  t.integer :tokens_used
  t.timestamps
end

add_index :ai_analyses, :analysis_type
add_index :ai_analyses, :created_at
```

### 3.2 Controllers Structure

**`app/controllers/dashboard/`:**
```
dashboard/
├── base_controller.rb           # Authentication & layout
├── dashboard_controller.rb      # Main overview
├── api_keys_controller.rb       # API key management
├── smtp_credentials_controller.rb  # SMTP credentials
├── webhooks_controller.rb       # Webhook configuration
├── templates_controller.rb      # Email templates
├── logs_controller.rb           # Email logs viewer
├── analytics_controller.rb      # Statistics & charts
└── ai_analytics_controller.rb   # AI analysis
```

### 3.3 Dashboard Routes

**`config/routes.rb`:**
```ruby
namespace :dashboard do
  root to: 'dashboard#index'

  resources :api_keys, except: [:show] do
    member do
      patch :toggle_active
    end
  end

  resources :smtp_credentials, except: [:show] do
    member do
      patch :toggle_active
      post :test_connection
    end
  end

  resources :webhooks do
    member do
      post :test
      post :retry_failed
    end
    collection do
      get :logs
    end
  end

  resources :templates

  resources :logs, only: [:index, :show] do
    collection do
      get :export
    end
  end

  resource :analytics, only: [:show] do
    get :hourly
    get :daily
    get :campaigns
  end

  resource :ai_analytics, only: [:show] do
    post :analyze_bounces
    post :optimize_timing
    post :compare_campaigns
    get :history
  end

  resource :settings, only: [:show, :update]
end
```

### 3.4 Dashboard UI (Views)

**Layout:** `app/views/layouts/dashboard.html.erb`
- Sidebar navigation
- Top header with user info
- Notifications area
- Responsive (Tailwind CSS)

**Pages:**
1. **Overview** (`dashboard/index.html.erb`)
   - Today's statistics (cards)
   - Recent activity
   - Quick actions
   - System health status

2. **API Keys** (`dashboard/api_keys/index.html.erb`)
   - Table with all keys
   - Create new key button
   - Copy to clipboard
   - Deactivate/Delete actions
   - Usage statistics per key

3. **SMTP Settings** (`dashboard/smtp_credentials/index.html.erb`)
   - Display connection info:
     ```
     SMTP Host: linenarrow.com
     SMTP Port: 587
     SMTP Security: TLS/STARTTLS
     Username: smtp_user_abc123
     Password: [Generated Password]
     ```
   - Create new credentials
   - Test connection button
   - Active/Inactive toggle

4. **Webhooks** (`dashboard/webhooks/index.html.erb`)
   - Add webhook URL
   - Select events to send
   - Test webhook button
   - Webhook delivery logs
   - Retry failed deliveries

5. **Templates** (`dashboard/templates/index.html.erb`)
   - List all templates
   - Create/Edit template
   - Preview template
   - Test send

6. **Logs** (`dashboard/logs/index.html.erb`)
   - Table with pagination
   - Filters (status, campaign, date range)
   - Search by recipient
   - Export to CSV
   - Detailed view modal

7. **Analytics** (`dashboard/analytics/show.html.erb`)
   - Charts (Chart.js):
     - Sent per hour (line)
     - Delivery status (pie)
     - Open/Click rates (bar)
     - Bounce rate trend (line)
   - Top campaigns table
   - Top domains table

8. **AI Analytics** (`dashboard/ai_analytics/show.html.erb`)
   - AI Settings section:
     - OpenRouter API Key input
     - Model selector
     - Temperature slider
     - Enable/Disable toggle
   - Analysis actions:
     - "Analyze Bounce Reasons" button
     - "Optimize Send Time" button
     - "Compare Campaigns" button
   - Analysis history
   - Display results (markdown formatted)

---

## 🤖 PHASE 4: AI ANALYTICS WITH OPENROUTER

### 4.1 OpenRouter Client Service

**`app/services/ai/openrouter_client.rb`:**
```ruby
module Ai
  class OpenrouterClient
    API_URL = 'https://openrouter.ai/api/v1/chat/completions'

    def initialize(api_key: nil, model: nil)
      @api_key = api_key || AiSetting.instance&.openrouter_api_key
      @model = model || AiSetting.instance&.model_name || 'anthropic/claude-3.5-sonnet'
    end

    def chat(messages, temperature: 0.7, max_tokens: 4000)
      response = HTTP.post(API_URL,
        headers: {
          'Authorization' => "Bearer #{@api_key}",
          'Content-Type' => 'application/json',
          'HTTP-Referer' => ENV['DOMAIN'],
          'X-Title' => 'Email Sender AI Analytics'
        },
        json: {
          model: @model,
          messages: messages,
          temperature: temperature,
          max_tokens: max_tokens
        }
      )

      JSON.parse(response.body)
    end

    def analyze(prompt, context_data)
      messages = [
        {
          role: 'system',
          content: 'You are an expert email deliverability analyst. Analyze email sending data and provide actionable insights.'
        },
        {
          role: 'user',
          content: build_analysis_prompt(prompt, context_data)
        }
      ]

      chat(messages)
    end

    private

    def build_analysis_prompt(prompt, data)
      "#{prompt}\n\nData:\n```json\n#{data.to_json}\n```"
    end
  end
end
```

### 4.2 Log Analyzer Service

**`app/services/ai/log_analyzer.rb`:**
```ruby
module Ai
  class LogAnalyzer
    def self.analyze_bounces(period:)
      bounces = EmailLog.bounced
                        .where(created_at: period)
                        .includes(:tracking_events)
                        .limit(1000)

      bounce_data = bounces.map do |log|
        {
          recipient_domain: log.recipient_masked.split('@').last,
          status_details: log.status_details,
          smtp_response: extract_smtp_response(log),
          timestamp: log.created_at
        }
      end

      prompt = <<~PROMPT
        Analyze these email bounce logs and provide:

        1. Main bounce categories (group similar reasons)
        2. Percentage of each category
        3. Specific recommendations to reduce bounces
        4. Problematic recipient domains
        5. Whether bounces are temporary (4xx) or permanent (5xx)

        Format the response in markdown with clear sections.
      PROMPT

      client = OpenrouterClient.new
      result = client.analyze(prompt, bounce_data)

      save_analysis('bounce_analysis', period, prompt, result)
    end

    def self.optimize_send_time(period:)
      opens = TrackingEvent.where(event_type: 'open', created_at: period)
                           .group_by_hour(:created_at, format: '%l %p')
                           .count

      prompt = <<~PROMPT
        Based on email open times over the past #{period.count} days:

        1. What are the best hours to send emails?
        2. What are the best days of the week?
        3. What times should be avoided?
        4. Segment recommendations (if patterns exist)

        Provide specific time windows (e.g., "Mon-Fri 9-11 AM EST").
      PROMPT

      client = OpenrouterClient.new
      result = client.analyze(prompt, opens)

      save_analysis('time_optimization', period, prompt, result)
    end

    def self.compare_campaigns
      campaigns = CampaignStat.order(total_sent: :desc).limit(20)

      campaign_data = campaigns.map do |c|
        {
          campaign_id: c.campaign_id,
          sent: c.total_sent,
          delivered: c.delivered,
          opened: c.opened,
          clicked: c.clicked,
          bounced: c.bounced,
          delivery_rate: (c.delivered.to_f / c.total_sent * 100).round(2),
          open_rate: (c.opened.to_f / c.delivered * 100).round(2),
          click_rate: (c.clicked.to_f / c.opened * 100).round(2)
        }
      end

      prompt = <<~PROMPT
        Compare these email campaigns:

        1. Rank campaigns by overall effectiveness
        2. Identify best performers (and why)
        3. Identify worst performers (and what went wrong)
        4. Common patterns in successful campaigns
        5. Actionable recommendations for future campaigns
      PROMPT

      client = OpenrouterClient.new
      result = client.analyze(prompt, campaign_data)

      save_analysis('campaign_comparison', 30.days.ago..Time.current, prompt, result)
    end

    private

    def self.extract_smtp_response(log)
      log.status_details&.dig('smtp_response') ||
      log.status_details&.dig('message') ||
      'Unknown'
    end

    def self.save_analysis(type, period, prompt, result)
      AiAnalysis.create!(
        analysis_type: type,
        period_start: period.is_a?(Range) ? period.begin : period,
        period_end: period.is_a?(Range) ? period.end : Time.current,
        prompt: prompt,
        result: result.dig('choices', 0, 'message', 'content'),
        tokens_used: result.dig('usage', 'total_tokens'),
        metadata: {
          model: result['model'],
          finish_reason: result.dig('choices', 0, 'finish_reason')
        }
      )
    end
  end
end
```

### 4.3 AI Analytics Controller

**`app/controllers/dashboard/ai_analytics_controller.rb`:**
```ruby
module Dashboard
  class AiAnalyticsController < BaseController
    def show
      @ai_setting = AiSetting.instance || AiSetting.create!
      @recent_analyses = AiAnalysis.order(created_at: :desc).limit(10)
    end

    def analyze_bounces
      period = parse_period(params[:period] || '24h')

      AnalyzeBouncesJob.perform_later(
        period: period,
        user_id: current_user.id
      )

      render json: { status: 'processing', message: 'Analysis started. Check back in a few moments.' }
    end

    def optimize_timing
      period = parse_period(params[:period] || '30d')

      OptimizeSendTimeJob.perform_later(period: period)

      render json: { status: 'processing' }
    end

    def compare_campaigns
      CompareCampaignsJob.perform_later

      render json: { status: 'processing' }
    end

    def history
      @analyses = AiAnalysis.order(created_at: :desc).page(params[:page])
    end

    private

    def parse_period(period_string)
      case period_string
      when '24h' then 24.hours.ago..Time.current
      when '7d' then 7.days.ago..Time.current
      when '30d' then 30.days.ago..Time.current
      else 24.hours.ago..Time.current
      end
    end
  end
end
```

---

## 🔄 PHASE 5: COMPLETE EMAIL FLOW

### Flow Diagram:
```
1. AMS connects to Haraka (port 587, TLS, AUTH)
   └─> AUTH LOGIN with credentials from Dashboard

2. AMS sends email via SMTP (MAIL FROM, RCPT TO, DATA)
   └─> Haraka receives full MIME message

3. Haraka plugins process:
   ├─> parse_email.js: Parse MIME structure
   ├─> rebuild_headers.js: Remove AMS traces, generate new Message-ID
   ├─> inject_tracking.js: Add tracking pixel & rewrite links
   └─> forward_to_api.js: POST to Rails API

4. Rails API receives:
   └─> POST /api/v1/smtp/receive
       ├─> Create EmailLog record
       ├─> Queue BuildEmailJob
       └─> Return 202 Accepted

5. Sidekiq processes:
   └─> BuildEmailJob
       ├─> Render template (if template_id)
       ├─> Inject tracking (already done by Haraka)
       └─> Queue SendToPostalJob

6. SendToPostalJob:
   └─> POST to Postal API
       ├─> Endpoint: http://postal:5000/api/v1/send/message
       ├─> Body: { to, from, subject, html_body, plain_body, attachments }
       └─> Update EmailLog status

7. Postal processes:
   ├─> Signs with DKIM
   ├─> Adds SPF records
   └─> Sends via SMTP to recipient

8. Tracking events:
   ├─> User opens email → /track/o → TrackingEvent created → Webhook to AMS
   └─> User clicks link → /track/c → TrackingEvent created → Webhook to AMS

9. Postal webhooks:
   └─> POST /api/v1/webhook
       ├─> Update EmailLog status
       └─> Send webhook to AMS (via WebhookEndpoint)
```

---

## 📝 PHASE 6: TESTING CHECKLIST

### 6.1 Configuration Tests
- [ ] `.env` file exists with all secrets
- [ ] `postal.yml` has real passwords (no ${VARIABLE})
- [ ] `htpasswd` file exists
- [ ] Nginx config is valid (`nginx -t`)

### 6.2 Service Health Tests
- [ ] All Docker containers running
- [ ] PostgreSQL healthy
- [ ] MariaDB healthy
- [ ] Redis healthy
- [ ] RabbitMQ healthy
- [ ] Postal healthy
- [ ] API healthy
- [ ] SMTP Relay healthy

### 6.3 Postal Tests
- [ ] Postal Web UI accessible at `/postal/`
- [ ] Can create organization
- [ ] Can create mail server
- [ ] Can add domain
- [ ] DKIM record generated
- [ ] API credential created

### 6.4 Dashboard Tests
- [ ] Dashboard accessible at `/dashboard`
- [ ] Can login with admin credentials
- [ ] Overview page shows statistics
- [ ] Can create API key
- [ ] Can create SMTP credentials
- [ ] Can configure webhook
- [ ] Can view logs
- [ ] Can see analytics charts

### 6.5 SMTP Relay Tests
- [ ] Port 587 listening
- [ ] TLS handshake succeeds
- [ ] AUTH PLAIN works
- [ ] AUTH LOGIN works
- [ ] Can receive MIME email
- [ ] Parses multipart/mixed
- [ ] Extracts attachments
- [ ] Rebuilds headers (removes AMS)
- [ ] Injects tracking
- [ ] Forwards to Rails API

### 6.6 End-to-End Tests
- [ ] Configure AMS with SMTP credentials
- [ ] AMS sends test email
- [ ] Haraka receives and processes
- [ ] Rails API creates EmailLog
- [ ] Sidekiq processes job
- [ ] Postal sends email
- [ ] Email delivered to recipient
- [ ] Tracking pixel works
- [ ] Click tracking works
- [ ] Webhook sent to AMS
- [ ] Dashboard shows statistics

### 6.7 AI Analytics Tests
- [ ] Can save OpenRouter API key
- [ ] Can select AI model
- [ ] Bounce analysis works
- [ ] Send time optimization works
- [ ] Campaign comparison works
- [ ] Results saved to database
- [ ] Results displayed in dashboard
- [ ] History page works

---

## 🚀 DEPLOYMENT STEPS

### Step 1: Pre-deployment
```bash
# 1. Verify .env configuration
cat .env | grep -v "^#" | grep -v "^$"

# 2. Verify postal.yml (no ${VARIABLE})
grep -E '\$\{' config/postal.yml && echo "ERROR: Variables not substituted!" || echo "OK"

# 3. Verify htpasswd exists
ls -l config/htpasswd

# 4. Build all services
docker compose build
```

### Step 2: Start services
```bash
# 1. Start databases first
docker compose up -d postgres mariadb redis rabbitmq

# 2. Wait for databases
sleep 60

# 3. Check database health
docker compose exec postgres pg_isready
docker compose exec mariadb mysqladmin ping

# 4. Start all other services
docker compose up -d
```

### Step 3: Initialize Postal
```bash
# 1. Initialize database
docker compose exec postal postal initialize

# 2. Create admin user
docker compose exec postal postal make-user
# Email: admin@linenarrow.com
# Password: [strong password]

# 3. Get DKIM record
docker compose exec postal postal default-dkim-record
```

### Step 4: Initialize Rails
```bash
# 1. Create database
docker compose exec api rails db:create

# 2. Run migrations
docker compose exec api rails db:migrate

# 3. Create API key for SMTP Relay
docker compose exec api rails runner "
  api_key, raw_key = ApiKey.generate(name: 'SMTP Relay Internal')
  puts '=' * 60
  puts 'SMTP_RELAY_API_KEY: ' + raw_key
  puts '=' * 60
"

# 4. Update .env with SMTP_RELAY_API_KEY
nano .env
# Add: SMTP_RELAY_API_KEY=<generated_key>

# 5. Restart services
docker compose restart api sidekiq smtp-relay
```

### Step 5: Configure Postal
```bash
# 1. Open Postal Web UI
# URL: http://localhost/postal/
# Login: admin@linenarrow.com

# 2. Create Organization
# 3. Create Mail Server
# 4. Add Domain: linenarrow.com
# 5. Generate API Credential
# 6. Copy API Key

# 7. Update .env
nano .env
# Add: POSTAL_API_KEY=<postal_api_key>

# 8. Restart
docker compose restart api sidekiq
```

### Step 6: Configure Dashboard
```bash
# 1. Open Dashboard
# URL: http://localhost/dashboard
# Login: admin / DBbNm9X11lHVivPI

# 2. Create SMTP Credentials
# Dashboard → SMTP Settings → Create New
# Copy: username, password

# 3. Configure Webhook
# Dashboard → Webhooks → Add Webhook
# URL: https://ams.example.com/api/webhooks/send_server

# 4. (Optional) Configure AI
# Dashboard → AI Analytics → Settings
# OpenRouter API Key: sk-or-...
# Model: anthropic/claude-3.5-sonnet
# Enable: ✓
```

### Step 7: Configure AMS
```bash
# In AMS Enterprise:
# 1. Go to Email Settings
# 2. Add SMTP Server:
#    Host: linenarrow.com
#    Port: 587
#    Security: TLS/STARTTLS
#    Username: <from_dashboard>
#    Password: <from_dashboard>
# 3. Test Connection
# 4. Send Test Email
```

### Step 8: Verify
```bash
# 1. Check logs
docker compose logs -f smtp-relay api sidekiq postal

# 2. Check Dashboard
# View email in Logs section

# 3. Check tracking
# Open email → verify pixel loads
# Click link → verify redirect works

# 4. Check webhook
# Dashboard → Webhooks → Logs
```

---

## 📊 MONITORING & MAINTENANCE

### Health Checks
```bash
# All services
curl http://localhost/health

# SMTP Relay
nc -zv localhost 587

# Postal
curl http://localhost:5000/health

# Dashboard
curl http://localhost/dashboard
```

### Logs
```bash
# All logs
docker compose logs -f

# Specific service
docker compose logs -f smtp-relay
docker compose logs -f api
docker compose logs -f postal
```

### Database Backups
```bash
# PostgreSQL
docker compose exec postgres pg_dump -U email_sender email_sender > backup_postgres.sql

# MariaDB
docker compose exec mariadb mysqldump -u postal -p postal > backup_mariadb.sql
```

### Performance Monitoring
- Dashboard → Analytics → System Resources
- Sidekiq Web UI → Queues
- Postal Web UI → Statistics

---

## 🎓 USER GUIDE

### For System Administrator

**Initial Setup:**
1. Deploy system using deployment steps
2. Configure DNS records (A, MX, SPF, DKIM, DMARC)
3. Set up SSL certificates (Let's Encrypt)
4. Create SMTP credentials in Dashboard
5. Provide credentials to AMS team

**Daily Operations:**
1. Check Dashboard overview for statistics
2. Monitor bounce rate (should be < 2%)
3. Review webhook delivery status
4. Run AI analysis weekly

**Troubleshooting:**
- Check `/health` endpoint
- Review logs in Dashboard
- Check Sidekiq queues
- Verify Postal is sending

### For AMS Team

**Setup:**
1. Get SMTP credentials from admin
2. Configure AMS with credentials:
   - Host: linenarrow.com
   - Port: 587
   - Security: TLS
3. Test connection
4. Send test email

**Monitoring:**
1. AMS receives webhooks for all events
2. Check email status via webhook data
3. Contact admin if delivery rate drops

---

## 📚 NEXT STEPS

After implementing this plan:
1. Comprehensive testing
2. Documentation updates
3. Performance optimization
4. Security audit
5. Production deployment
6. Training for users

---

**Status:** Ready for implementation
**Estimated Time:** 15-20 hours
**Complexity:** High
**Dependencies:** Docker, Postal, Haraka, OpenRouter API
