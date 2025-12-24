# Cursor Prompts для Email Sender Infrastructure

**Инструкция:** Выполняй промты последовательно. После каждого промта проверь что всё работает, потом переходи к следующему.

---

## ФАЗА 1: Критические баги (без этого проект не запустится)

```
Исправь критические баги в проекте. Делай ТОЧНО как описано, не импровизируй.

### 1. Создай модель EmailTemplate

Создай файл `app/models/email_template.rb`:

class EmailTemplate < ApplicationRecord
  has_many :email_logs, foreign_key: :template_id, dependent: :nullify

  validates :external_id, presence: true, uniqueness: true
  validates :name, presence: true, length: { maximum: 255 }
  validates :html_content, presence: true

  scope :active, -> { where(active: true) }

  def self.find_by_external_id(external_id)
    find_by(external_id: external_id)
  end

  def render(variables = {})
    Liquid::Template.parse(html_content).render(variables.stringify_keys)
  rescue Liquid::Error => e
    Rails.logger.error("Template render error: #{e.message}")
    html_content
  end
end

### 2. Создай миграцию для email_templates

Создай файл `db/migrate/002_create_email_templates.rb`:

class CreateEmailTemplates < ActiveRecord::Migration[7.1]
  def change
    create_table :email_templates do |t|
      t.string :external_id, null: false, limit: 64
      t.string :name, null: false, limit: 255
      t.text :html_content, null: false
      t.text :plain_content
      t.jsonb :variables, default: []
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :email_templates, :external_id, unique: true
    add_index :email_templates, :active
  end
end

### 3. Создай BuildEmailJob

Создай файл `app/jobs/build_email_job.rb`:

class BuildEmailJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(email_log_id)
    email_log = EmailLog.find(email_log_id)
    
    return if email_log.status == 'sent' || email_log.status == 'delivered'
    
    email_log.update!(status: 'processing')

    # Рендерим шаблон
    html_body = render_html(email_log)
    
    # Инжектируем трекинг
    domain = ENV.fetch('DOMAIN', 'localhost')
    html_body = TrackingInjector.inject_all(
      html: html_body,
      recipient: email_log.recipient,
      campaign_id: email_log.campaign_id,
      message_id: email_log.external_message_id,
      domain: domain
    )

    # Отправляем в Postal
    SendToPostalJob.perform_async(email_log.id, html_body)
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn("BuildEmailJob: EmailLog #{email_log_id} not found, skipping")
  end

  private

  def render_html(email_log)
    template = email_log.template
    variables = email_log.status_details&.dig('variables') || {}

    if template
      template.render(variables)
    else
      build_default_html(email_log, variables)
    end
  end

  def build_default_html(email_log, variables)
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><meta charset="utf-8"></head>
      <body>
        <p>#{variables['body'] || 'Email content'}</p>
      </body>
      </html>
    HTML
  end
end

### 4. Заполни JobHelper

Замени содержимое `app/lib/job_helper.rb` на:

module JobHelper
  def self.enqueue(job_class, *args)
    if args.compact.empty?
      Rails.logger.warn("JobHelper.enqueue called with empty args for #{job_class}")
      return
    end

    job_class.perform_async(*args.compact)
  rescue => e
    Rails.logger.error("JobHelper.enqueue failed for #{job_class}: #{e.message}")
    
    # Fallback для development/test
    if Rails.env.development? || Rails.env.test?
      job_class.new.perform(*args.compact)
    end
  end

  def self.enqueue_in(delay, job_class, *args)
    job_class.perform_in(delay, *args.compact)
  rescue => e
    Rails.logger.error("JobHelper.enqueue_in failed: #{e.message}")
  end
end

### 5. Исправь HealthController namespace

Перемести `app/controllers/health_controller.rb` в `app/controllers/api/v1/health_controller.rb` и измени класс:

module Api
  module V1
    class HealthController < ActionController::API
      # ... оставь всё содержимое метода show как есть, только оберни в module Api и module V1
    end
  end
end

### 6. Создай TemplatesController

Создай файл `app/controllers/api/v1/templates_controller.rb`:

module Api
  module V1
    class TemplatesController < Api::V1::ApplicationController
      def create
        template = EmailTemplate.new(template_params)

        if template.save
          render json: {
            id: template.id,
            external_id: template.external_id,
            name: template.name,
            created_at: template.created_at.iso8601
          }, status: :created
        else
          render json: {
            error: {
              code: 'validation_error',
              message: 'Template creation failed',
              details: template.errors.full_messages
            }
          }, status: :unprocessable_entity
        end
      end

      private

      def template_params
        params.permit(:external_id, :name, :html_content, :plain_content, variables: [])
      end
    end
  end
end

### 7. Исправь дублирующийся индекс в миграции

В файле `db/migrate/001_create_api_keys.rb` удали строку 15:
    add_index :api_keys, :key_hash, unique: true

Оставь только partial index на строке 16 и измени его на:
    add_index :api_keys, :key_hash, unique: true, where: "active = true", name: "idx_api_keys_active_unique"

После всех изменений проверь что нет синтаксических ошибок.
```

---

## ФАЗА 2: Безопасность

```
Добавь критические компоненты безопасности. Делай ТОЧНО как описано.

### 1. Webhook signature verification

В файле `app/controllers/api/v1/webhooks_controller.rb` добавь before_action и приватный метод:

class Api::V1::WebhooksController < Api::V1::ApplicationController
  skip_before_action :authenticate_api_key
  before_action :verify_postal_signature, only: [:postal]

  def postal
    # ... существующий код без изменений
  end

  private

  def verify_postal_signature
    signature = request.headers['X-Postal-Signature']
    
    unless signature.present?
      Rails.logger.warn("Webhook without signature from #{request.remote_ip}")
      return head :unauthorized
    end

    signing_key = ENV.fetch('POSTAL_SIGNING_KEY', '')
    
    if signing_key.blank?
      Rails.logger.error("POSTAL_SIGNING_KEY not configured")
      return head :internal_server_error
    end

    payload = request.raw_post
    expected_signature = OpenSSL::HMAC.hexdigest('SHA256', signing_key, payload)

    unless ActiveSupport::SecurityUtils.secure_compare(signature, expected_signature)
      Rails.logger.warn("Invalid webhook signature from #{request.remote_ip}")
      return head :unauthorized
    end
  end
end

### 2. Защити Sidekiq Web UI

Замени содержимое `config/routes.rb` на:

require 'sidekiq/web'

# Sidekiq Web UI authentication
Sidekiq::Web.use(Rack::Auth::Basic) do |username, password|
  ActiveSupport::SecurityUtils.secure_compare(
    ::Digest::SHA256.hexdigest(username),
    ::Digest::SHA256.hexdigest(ENV.fetch('SIDEKIQ_USERNAME', 'admin'))
  ) & ActiveSupport::SecurityUtils.secure_compare(
    ::Digest::SHA256.hexdigest(password),
    ::Digest::SHA256.hexdigest(ENV.fetch('SIDEKIQ_PASSWORD', 'admin'))
  )
end

Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      get 'health', to: 'health#show'
      post 'send', to: 'emails#send_email'
      post 'batch', to: 'batches#create'
      get 'status/:message_id', to: 'status#show', as: 'status'
      get 'stats', to: 'stats#index'
      post 'templates', to: 'templates#create'
      post 'webhook', to: 'webhooks#postal'
    end
  end

  get 'dashboard', to: 'dashboard#index', as: 'dashboard_index'
  get 'dashboard/logs', to: 'dashboard#logs', as: 'dashboard_logs'
  
  get 'unsubscribe/:token', to: 'unsubscribe#show', as: 'unsubscribe'
  post 'unsubscribe/:token', to: 'unsubscribe#create'

  mount Sidekiq::Web => '/sidekiq'
end

### 3. Настрой CORS правильно

В файле `config/application.rb` замени блок CORS (строки 34-41) на:

    # CORS - только разрешённые домены
    allowed_origins = ENV.fetch('ALLOWED_ORIGINS', 'http://localhost:3000').split(',').map(&:strip)
    
    config.middleware.insert_before 0, Rack::Cors do
      allow do
        origins(*allowed_origins)
        resource '/api/*',
          headers: :any,
          methods: [:get, :post, :put, :patch, :delete, :options],
          expose: ['X-Request-Id', 'X-RateLimit-Remaining'],
          max_age: 600
      end
    end

### 4. Настрой Rack::Attack

Замени содержимое `config/initializers/rack_attack.rb` на:

class Rack::Attack
  # Кэш в Redis
  Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(
    url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')
  )

  # Throttle API по IP: 100 req/min
  throttle('api/ip', limit: 100, period: 1.minute) do |req|
    req.ip if req.path.start_with?('/api/')
  end

  # Throttle API по API key: 1000 req/min
  throttle('api/key', limit: 1000, period: 1.minute) do |req|
    if req.path.start_with?('/api/') && req.env['HTTP_AUTHORIZATION'].present?
      token = req.env['HTTP_AUTHORIZATION'].to_s.split(' ').last
      Digest::SHA256.hexdigest(token)[0..15] if token.present?
    end
  end

  # Throttle batch endpoint строже: 10 req/min per IP
  throttle('api/batch', limit: 10, period: 1.minute) do |req|
    req.ip if req.path == '/api/v1/batch' && req.post?
  end

  # Ban после 5 неудачных auth попыток
  blocklist('fail2ban') do |req|
    Rack::Attack::Allow2Ban.filter(req.ip, maxretry: 5, findtime: 1.minute, bantime: 1.hour) do
      req.path.start_with?('/api/') && req.env['warden']&.user.nil? && req.env['HTTP_AUTHORIZATION'].present?
    end
  end

  # Response для throttled requests
  self.throttled_responder = lambda do |req|
    retry_after = (req.env['rack.attack.match_data'] || {})[:period]
    [
      429,
      {
        'Content-Type' => 'application/json',
        'Retry-After' => retry_after.to_s
      },
      [{
        error: {
          code: 'rate_limit_exceeded',
          message: 'Too many requests',
          retry_after: retry_after
        }
      }.to_json]
    ]
  end

  # Response для blocked requests
  self.blocklisted_responder = lambda do |req|
    [
      403,
      { 'Content-Type' => 'application/json' },
      [{ error: { code: 'blocked', message: 'Access denied' } }.to_json]
    ]
  end
end

### 5. Включи SSL в production

В файле `config/environments/production.rb` раскомментируй и измени строку 38:

  config.force_ssl = true
  config.ssl_options = { hsts: { subdomains: true, preload: true, expires: 1.year } }

### 6. Удали debug output

В файле `app/services/api_key_authenticator.rb` удали строки 16-17 и 21-22 (все $stderr.puts).

Файл должен выглядеть так:

class ApiKeyAuthenticator
  def self.call(token)
    return nil if token.blank?

    key_hash = Digest::SHA256.hexdigest(token)
    api_key = ApiKey.find_by(key_hash: key_hash, active: true)

    if api_key
      begin
        api_key.touch_last_used
      rescue => e
        Rails.logger.error("ApiKeyAuthenticator: Failed to touch_last_used: #{e.message}")
      end
      api_key
    end
  end
end

После изменений проверь что приложение запускается без ошибок.
```

---

## ФАЗА 3: Расширение модели данных для аналитики

```
Расширь модели и добавь новые компоненты для аналитики доставки. Делай ТОЧНО как описано.

### 1. Создай миграцию для расширения email_logs

Создай файл `db/migrate/006_extend_email_logs_for_analytics.rb`:

class ExtendEmailLogsForAnalytics < ActiveRecord::Migration[7.1]
  def change
    add_column :email_logs, :bounce_type, :string, limit: 10
    add_column :email_logs, :smtp_code, :string, limit: 10
    add_column :email_logs, :error_message, :text
    add_column :email_logs, :recipient_domain, :string, limit: 255
    add_column :email_logs, :retry_count, :integer, default: 0, null: false
    add_column :email_logs, :next_retry_at, :timestamp
    add_column :email_logs, :provider_message_id, :string, limit: 255

    add_index :email_logs, :bounce_type
    add_index :email_logs, :smtp_code
    add_index :email_logs, :recipient_domain
    add_index :email_logs, :next_retry_at, where: "status = 'retry_scheduled'"
    add_index :email_logs, [:recipient_domain, :status], name: 'idx_logs_domain_status'
    add_index :email_logs, [:created_at, :status], name: 'idx_logs_created_status'
    
    add_check_constraint :email_logs, 
      "bounce_type IS NULL OR bounce_type IN ('hard', 'soft')", 
      name: 'email_logs_bounce_type_check'
  end
end

### 2. Обнови модель EmailLog

Добавь в `app/models/email_log.rb` после строки validates:

  # Добавь эти статусы в inclusion
  validates :status, presence: true, inclusion: { 
    in: %w[queued processing sent delivered bounced failed complained retry_scheduled] 
  }
  validates :bounce_type, inclusion: { in: %w[hard soft], allow_nil: true }

  # Callbacks
  before_save :extract_recipient_domain

  # Scopes
  scope :pending_retry, -> { where(status: 'retry_scheduled').where('next_retry_at <= ?', Time.current) }
  scope :by_domain, ->(domain) { where(recipient_domain: domain) }
  scope :bounced_hard, -> { where(bounce_type: 'hard') }
  scope :bounced_soft, -> { where(bounce_type: 'soft') }
  scope :recent, ->(hours = 24) { where('created_at >= ?', hours.hours.ago) }

  # Methods
  def schedule_retry(delay: nil)
    return false if bounce_type == 'hard' || retry_count >= 3

    delay ||= [1.hour, 4.hours, 24.hours][retry_count] || 24.hours
    
    update!(
      status: 'retry_scheduled',
      retry_count: retry_count + 1,
      next_retry_at: Time.current + delay
    )
  end

  def record_bounce(type:, smtp_code: nil, message: nil)
    update!(
      status: 'bounced',
      bounce_type: type,
      smtp_code: smtp_code,
      error_message: message&.truncate(1000)
    )
  end

  private

  def extract_recipient_domain
    return unless recipient.present? && recipient_changed?
    
    self.recipient_domain = recipient.split('@').last&.downcase
  end

### 3. Создай модель Blacklist

Создай файл `db/migrate/007_create_blacklists.rb`:

class CreateBlacklists < ActiveRecord::Migration[7.1]
  def change
    create_table :blacklists do |t|
      t.string :email, null: false
      t.string :email_hash, null: false, limit: 64
      t.string :reason, null: false, limit: 50
      t.string :source, limit: 50
      t.text :details
      t.timestamp :expires_at

      t.timestamps
    end

    add_index :blacklists, :email_hash, unique: true
    add_index :blacklists, :reason
    add_index :blacklists, :expires_at, where: 'expires_at IS NOT NULL'
  end
end

Создай файл `app/models/blacklist.rb`:

class Blacklist < ApplicationRecord
  REASONS = %w[hard_bounce complaint manual fbl spam_trap].freeze

  validates :email, presence: true
  validates :email_hash, presence: true, uniqueness: true
  validates :reason, presence: true, inclusion: { in: REASONS }

  before_validation :set_email_hash

  scope :active, -> { where('expires_at IS NULL OR expires_at > ?', Time.current) }
  scope :by_reason, ->(reason) { where(reason: reason) }

  def self.blocked?(email)
    return false if email.blank?
    
    hash = Digest::SHA256.hexdigest(email.downcase.strip)
    active.exists?(email_hash: hash)
  end

  def self.add(email, reason:, source: nil, details: nil, expires_in: nil)
    email = email.downcase.strip
    hash = Digest::SHA256.hexdigest(email)

    record = find_or_initialize_by(email_hash: hash)
    record.assign_attributes(
      email: email,
      reason: reason,
      source: source,
      details: details,
      expires_at: expires_in ? Time.current + expires_in : nil
    )
    record.save!
    record
  rescue ActiveRecord::RecordNotUnique
    find_by(email_hash: hash)
  end

  def self.remove(email)
    hash = Digest::SHA256.hexdigest(email.downcase.strip)
    find_by(email_hash: hash)&.destroy
  end

  private

  def set_email_hash
    self.email_hash = Digest::SHA256.hexdigest(email.downcase.strip) if email.present?
  end
end

### 4. Создай модель DiagnosticReport

Создай файл `db/migrate/008_create_diagnostic_reports.rb`:

class CreateDiagnosticReports < ActiveRecord::Migration[7.1]
  def change
    create_table :diagnostic_reports do |t|
      t.string :report_type, null: false, limit: 50
      t.string :severity, null: false, limit: 20
      t.jsonb :anomalies, default: []
      t.jsonb :stats, default: {}
      t.jsonb :context, default: {}
      t.text :ai_analysis
      t.text :recommended_actions
      t.string :status, default: 'pending', limit: 20
      t.timestamp :resolved_at
      t.text :resolution_notes

      t.timestamps
    end

    add_index :diagnostic_reports, :report_type
    add_index :diagnostic_reports, :severity
    add_index :diagnostic_reports, :status
    add_index :diagnostic_reports, :created_at
  end
end

Создай файл `app/models/diagnostic_report.rb`:

class DiagnosticReport < ApplicationRecord
  TYPES = %w[anomaly hourly_check manual ai_triggered].freeze
  SEVERITIES = %w[info warning critical].freeze
  STATUSES = %w[pending acknowledged resolved ignored].freeze

  validates :report_type, presence: true, inclusion: { in: TYPES }
  validates :severity, presence: true, inclusion: { in: SEVERITIES }
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :unresolved, -> { where(status: %w[pending acknowledged]) }
  scope :critical, -> { where(severity: 'critical') }
  scope :recent, ->(hours = 24) { where('created_at >= ?', hours.hours.ago) }

  def resolve!(notes: nil)
    update!(
      status: 'resolved',
      resolved_at: Time.current,
      resolution_notes: notes
    )
  end

  def acknowledge!
    update!(status: 'acknowledged')
  end
end

### 5. Создай модель HourlyStats для быстрой аналитики

Создай файл `db/migrate/009_create_hourly_stats.rb`:

class CreateHourlyStats < ActiveRecord::Migration[7.1]
  def change
    create_table :hourly_stats do |t|
      t.timestamp :hour, null: false
      t.string :domain, limit: 255
      t.integer :sent, default: 0, null: false
      t.integer :delivered, default: 0, null: false
      t.integer :bounced_hard, default: 0, null: false
      t.integer :bounced_soft, default: 0, null: false
      t.integer :complained, default: 0, null: false
      t.integer :opened, default: 0, null: false
      t.integer :clicked, default: 0, null: false
      t.decimal :delivery_rate, precision: 5, scale: 2
      t.decimal :bounce_rate, precision: 5, scale: 2
      t.decimal :complaint_rate, precision: 5, scale: 4

      t.timestamps
    end

    add_index :hourly_stats, [:hour, :domain], unique: true
    add_index :hourly_stats, :hour
    add_index :hourly_stats, :domain
  end
end

Создай файл `app/models/hourly_stats.rb`:

class HourlyStats < ApplicationRecord
  validates :hour, presence: true
  validates :hour, uniqueness: { scope: :domain }

  scope :for_hour, ->(time) { where(hour: time.beginning_of_hour) }
  scope :for_domain, ->(domain) { where(domain: domain) }
  scope :global, -> { where(domain: nil) }
  scope :last_24h, -> { where('hour >= ?', 24.hours.ago.beginning_of_hour) }

  def self.aggregate_hour(time, domain: nil)
    hour_start = time.beginning_of_hour
    hour_end = hour_start + 1.hour

    base = EmailLog.where(created_at: hour_start...hour_end)
    base = base.by_domain(domain) if domain

    stats = find_or_initialize_by(hour: hour_start, domain: domain)
    
    sent = base.where(status: %w[sent delivered bounced complained]).count
    delivered = base.where(status: 'delivered').count
    bounced_hard = base.bounced_hard.count
    bounced_soft = base.bounced_soft.count
    complained = base.where(status: 'complained').count

    # Tracking events
    log_ids = base.pluck(:id)
    opened = TrackingEvent.where(email_log_id: log_ids, event_type: 'open').select(:email_log_id).distinct.count
    clicked = TrackingEvent.where(email_log_id: log_ids, event_type: 'click').select(:email_log_id).distinct.count

    stats.update!(
      sent: sent,
      delivered: delivered,
      bounced_hard: bounced_hard,
      bounced_soft: bounced_soft,
      complained: complained,
      opened: opened,
      clicked: clicked,
      delivery_rate: sent > 0 ? (delivered.to_f / sent * 100).round(2) : 0,
      bounce_rate: sent > 0 ? ((bounced_hard + bounced_soft).to_f / sent * 100).round(2) : 0,
      complaint_rate: sent > 0 ? (complained.to_f / sent * 100).round(4) : 0
    )

    stats
  end
end

После создания всех файлов выполни: bundle exec rails db:migrate
```

---

## ФАЗА 4: AI-аналитика и мониторинг

```
Добавь систему мониторинга и AI-аналитики. Делай ТОЧНО как описано.

### 1. Создай DeliveryMonitor для детерминированных правил

Создай файл `app/services/delivery_monitor.rb`:

class DeliveryMonitor
  RETRY_DELAYS = [1.hour, 4.hours, 24.hours].freeze

  def self.process_bounce(email_log, smtp_code:, message:)
    bounce_type = classify_bounce(smtp_code, message)
    
    email_log.record_bounce(
      type: bounce_type,
      smtp_code: smtp_code,
      message: message
    )

    case bounce_type
    when 'hard'
      handle_hard_bounce(email_log)
    when 'soft'
      handle_soft_bounce(email_log, smtp_code)
    end
  end

  def self.process_complaint(email_log, source: 'fbl')
    email_log.update!(status: 'complained')
    
    Blacklist.add(
      email_log.recipient,
      reason: 'complaint',
      source: source,
      details: "Campaign: #{email_log.campaign_id}"
    )

    # Проверяем rate
    check_complaint_rate(email_log.campaign_id)
  end

  private

  def self.classify_bounce(smtp_code, message)
    return 'hard' if smtp_code&.start_with?('5')
    return 'soft' if smtp_code&.start_with?('4')

    message_lower = message.to_s.downcase
    
    hard_patterns = ['user unknown', 'mailbox not found', 'invalid recipient', 
                     'no such user', 'account disabled', 'address rejected']
    return 'hard' if hard_patterns.any? { |p| message_lower.include?(p) }

    soft_patterns = ['mailbox full', 'over quota', 'try again', 'temporarily',
                     'rate limit', 'too many', 'connection timeout']
    return 'soft' if soft_patterns.any? { |p| message_lower.include?(p) }

    # Default to soft if unclear
    'soft'
  end

  def self.handle_hard_bounce(email_log)
    Blacklist.add(
      email_log.recipient,
      reason: 'hard_bounce',
      source: 'smtp',
      details: "SMTP: #{email_log.smtp_code} - #{email_log.error_message&.truncate(200)}"
    )
  end

  def self.handle_soft_bounce(email_log, smtp_code)
    # 421 = rate limit, снижаем скорость
    if smtp_code == '421'
      RateController.reduce_rate(email_log.recipient_domain, factor: 0.5, duration: 1.hour)
    end

    # Планируем retry если не превышен лимит
    email_log.schedule_retry unless email_log.retry_count >= 3
  end

  def self.check_complaint_rate(campaign_id)
    stats = CampaignStats.find_by(campaign_id: campaign_id)
    return unless stats

    rate = stats.total_sent > 0 ? stats.total_complained.to_f / stats.total_sent : 0
    
    if rate > 0.001 # > 0.1%
      DiagnosticReport.create!(
        report_type: 'anomaly',
        severity: rate > 0.005 ? 'critical' : 'warning',
        anomalies: [{ metric: 'complaint_rate', value: (rate * 100).round(4), campaign_id: campaign_id }],
        stats: stats.attributes,
        recommended_actions: "Review campaign #{campaign_id} content and list quality"
      )

      NotificationService.alert(
        title: "High complaint rate: #{(rate * 100).round(3)}%",
        message: "Campaign #{campaign_id} has elevated complaints",
        severity: rate > 0.005 ? :critical : :warning
      )
    end
  end
end

### 2. Создай AnomalyDetector

Создай файл `app/services/anomaly_detector.rb`:

class AnomalyDetector
  THRESHOLDS = {
    bounce_rate: { warning: 5.0, critical: 10.0 },
    complaint_rate: { warning: 0.05, critical: 0.1 },
    delivery_rate_min: { warning: 95.0, critical: 90.0 },
    soft_bounce_rate: { warning: 3.0, critical: 7.0 }
  }.freeze

  def self.check_hourly
    new.check_hourly
  end

  def check_hourly
    stats = gather_last_hour_stats
    anomalies = detect_anomalies(stats)

    return if anomalies.empty?

    if simple_case?(anomalies)
      handle_automatically(anomalies, stats)
    else
      trigger_ai_analysis(anomalies, stats)
    end
  end

  private

  def gather_last_hour_stats
    hour_ago = 1.hour.ago
    logs = EmailLog.where('created_at >= ?', hour_ago)

    sent = logs.where(status: %w[sent delivered bounced complained]).count
    delivered = logs.where(status: 'delivered').count
    bounced = logs.where(status: 'bounced').count
    bounced_hard = logs.bounced_hard.count
    bounced_soft = logs.bounced_soft.count
    complained = logs.where(status: 'complained').count

    by_domain = logs.group(:recipient_domain).count
    bounce_by_domain = logs.where(status: 'bounced').group(:recipient_domain).count

    {
      sent: sent,
      delivered: delivered,
      bounced: bounced,
      bounced_hard: bounced_hard,
      bounced_soft: bounced_soft,
      complained: complained,
      delivery_rate: sent > 0 ? (delivered.to_f / sent * 100) : 100,
      bounce_rate: sent > 0 ? (bounced.to_f / sent * 100) : 0,
      soft_bounce_rate: sent > 0 ? (bounced_soft.to_f / sent * 100) : 0,
      complaint_rate: sent > 0 ? (complained.to_f / sent * 100) : 0,
      by_domain: by_domain,
      bounce_by_domain: bounce_by_domain,
      errors: recent_errors
    }
  end

  def recent_errors
    EmailLog
      .where('created_at >= ?', 1.hour.ago)
      .where.not(error_message: nil)
      .group(:smtp_code, :error_message)
      .count
      .map { |(code, msg), count| { smtp_code: code, message: msg&.truncate(100), count: count } }
      .sort_by { |e| -e[:count] }
      .first(10)
  end

  def detect_anomalies(stats)
    anomalies = []

    if stats[:bounce_rate] >= THRESHOLDS[:bounce_rate][:critical]
      anomalies << { metric: 'bounce_rate', value: stats[:bounce_rate].round(2), severity: :critical }
    elsif stats[:bounce_rate] >= THRESHOLDS[:bounce_rate][:warning]
      anomalies << { metric: 'bounce_rate', value: stats[:bounce_rate].round(2), severity: :warning }
    end

    if stats[:complaint_rate] >= THRESHOLDS[:complaint_rate][:critical]
      anomalies << { metric: 'complaint_rate', value: stats[:complaint_rate].round(4), severity: :critical }
    elsif stats[:complaint_rate] >= THRESHOLDS[:complaint_rate][:warning]
      anomalies << { metric: 'complaint_rate', value: stats[:complaint_rate].round(4), severity: :warning }
    end

    if stats[:delivery_rate] <= THRESHOLDS[:delivery_rate_min][:critical]
      anomalies << { metric: 'delivery_rate', value: stats[:delivery_rate].round(2), severity: :critical }
    elsif stats[:delivery_rate] <= THRESHOLDS[:delivery_rate_min][:warning]
      anomalies << { metric: 'delivery_rate', value: stats[:delivery_rate].round(2), severity: :warning }
    end

    anomalies
  end

  def simple_case?(anomalies)
    # Простой случай: одна warning-аномалия
    anomalies.size == 1 && anomalies.first[:severity] == :warning
  end

  def handle_automatically(anomalies, stats)
    anomaly = anomalies.first

    DiagnosticReport.create!(
      report_type: 'hourly_check',
      severity: anomaly[:severity].to_s,
      anomalies: anomalies,
      stats: stats.except(:errors),
      recommended_actions: auto_recommendation(anomaly, stats)
    )

    NotificationService.alert(
      title: "#{anomaly[:metric]} anomaly detected",
      message: "#{anomaly[:metric]}: #{anomaly[:value]}%",
      severity: anomaly[:severity]
    )
  end

  def auto_recommendation(anomaly, stats)
    case anomaly[:metric]
    when 'bounce_rate'
      if stats[:soft_bounce_rate] > stats[:bounced_hard].to_f / [stats[:sent], 1].max * 100
        "High soft bounce rate suggests temporary delivery issues. Monitor for resolution."
      else
        "High hard bounce rate indicates list quality issues. Review recent imports."
      end
    when 'complaint_rate'
      "Elevated complaints. Review recent campaign content and sending frequency."
    when 'delivery_rate'
      "Low delivery rate. Check provider-specific issues in bounce breakdown."
    else
      "Monitor situation and investigate if persists."
    end
  end

  def trigger_ai_analysis(anomalies, stats)
    AiDiagnostician.analyze_async(anomalies, stats)
  end
end

### 3. Создай AiDiagnostician

Создай файл `app/services/ai_diagnostician.rb`:

class AiDiagnostician
  def self.analyze_async(anomalies, stats)
    AiDiagnosticJob.perform_async(anomalies.as_json, stats.as_json)
  end

  def self.analyze(anomalies, stats)
    new.analyze(anomalies, stats)
  end

  def analyze(anomalies, stats)
    prompt = build_prompt(anomalies, stats)
    
    response = call_ai(prompt)
    
    report = DiagnosticReport.create!(
      report_type: 'ai_triggered',
      severity: max_severity(anomalies),
      anomalies: anomalies,
      stats: stats,
      ai_analysis: response[:analysis],
      recommended_actions: response[:actions]
    )

    NotificationService.alert(
      title: "AI Diagnostic Report",
      message: response[:summary],
      severity: max_severity(anomalies).to_sym,
      report_id: report.id
    )

    report
  end

  private

  def build_prompt(anomalies, stats)
    <<~PROMPT
      You are an email deliverability expert. Analyze this situation and provide actionable recommendations.

      ## Current Anomalies
      #{anomalies.map { |a| "- #{a['metric'] || a[:metric]}: #{a['value'] || a[:value]}% (#{a['severity'] || a[:severity]})" }.join("\n")}

      ## Last Hour Statistics
      - Sent: #{stats['sent'] || stats[:sent]}
      - Delivered: #{stats['delivered'] || stats[:delivered]} (#{(stats['delivery_rate'] || stats[:delivery_rate])&.round(1)}%)
      - Bounced: #{stats['bounced'] || stats[:bounced]} (hard: #{stats['bounced_hard'] || stats[:bounced_hard]}, soft: #{stats['bounced_soft'] || stats[:bounced_soft]})
      - Complaints: #{stats['complained'] || stats[:complained]}

      ## Recent Errors (top 10)
      #{format_errors(stats['errors'] || stats[:errors])}

      ## Domain Breakdown
      #{format_domain_stats(stats)}

      Provide your analysis in this exact JSON format:
      {
        "summary": "One sentence summary of the issue",
        "root_cause": "Most likely root cause",
        "analysis": "Detailed analysis (2-3 paragraphs)",
        "actions": ["Action 1", "Action 2", "Action 3"],
        "should_pause_sending": true/false,
        "urgency": "low/medium/high/critical"
      }
    PROMPT
  end

  def format_errors(errors)
    return "No errors recorded" if errors.blank?
    
    errors.first(10).map { |e| "- #{e['smtp_code'] || e[:smtp_code]}: #{e['message'] || e[:message]} (#{e['count'] || e[:count]}x)" }.join("\n")
  end

  def format_domain_stats(stats)
    by_domain = stats['by_domain'] || stats[:by_domain] || {}
    bounce_by_domain = stats['bounce_by_domain'] || stats[:bounce_by_domain] || {}
    
    return "No domain breakdown available" if by_domain.empty?

    by_domain.first(5).map do |domain, count|
      bounces = bounce_by_domain[domain] || 0
      rate = count > 0 ? (bounces.to_f / count * 100).round(1) : 0
      "- #{domain}: #{count} sent, #{rate}% bounce"
    end.join("\n")
  end

  def call_ai(prompt)
    # Используем Anthropic API
    api_key = ENV.fetch('ANTHROPIC_API_KEY', '')
    
    if api_key.blank?
      Rails.logger.warn("AiDiagnostician: ANTHROPIC_API_KEY not set, using fallback")
      return fallback_response
    end

    response = HTTParty.post(
      'https://api.anthropic.com/v1/messages',
      headers: {
        'Content-Type' => 'application/json',
        'x-api-key' => api_key,
        'anthropic-version' => '2023-06-01'
      },
      body: {
        model: 'claude-sonnet-4-20250514',
        max_tokens: 1024,
        messages: [{ role: 'user', content: prompt }]
      }.to_json,
      timeout: 30
    )

    if response.success?
      content = response.parsed_response.dig('content', 0, 'text')
      parse_ai_response(content)
    else
      Rails.logger.error("AI API error: #{response.code} - #{response.body}")
      fallback_response
    end
  rescue => e
    Rails.logger.error("AiDiagnostician error: #{e.message}")
    fallback_response
  end

  def parse_ai_response(content)
    # Извлекаем JSON из ответа
    json_match = content.match(/\{[\s\S]*\}/)
    
    if json_match
      parsed = JSON.parse(json_match[0])
      {
        summary: parsed['summary'] || 'Analysis complete',
        analysis: parsed['analysis'] || content,
        actions: parsed['actions']&.join("\n") || 'Review manually'
      }
    else
      { summary: 'Analysis complete', analysis: content, actions: 'Review the analysis above' }
    end
  rescue JSON::ParserError
    { summary: 'Analysis complete', analysis: content, actions: 'Review the analysis above' }
  end

  def fallback_response
    {
      summary: 'AI analysis unavailable - manual review required',
      analysis: 'Could not perform AI analysis. Please review the anomalies and stats manually.',
      actions: "1. Check recent campaign quality\n2. Review bounce messages\n3. Monitor for next hour"
    }
  end

  def max_severity(anomalies)
    return 'critical' if anomalies.any? { |a| (a['severity'] || a[:severity]).to_s == 'critical' }
    return 'warning' if anomalies.any? { |a| (a['severity'] || a[:severity]).to_s == 'warning' }
    'info'
  end
end

### 4. Создай AiDiagnosticJob

Создай файл `app/jobs/ai_diagnostic_job.rb`:

class AiDiagnosticJob < ApplicationJob
  queue_as :low

  def perform(anomalies, stats)
    AiDiagnostician.analyze(anomalies, stats)
  end
end

### 5. Создай NotificationService

Создай файл `app/services/notification_service.rb`:

class NotificationService
  def self.alert(title:, message:, severity: :info, report_id: nil)
    new.alert(title: title, message: message, severity: severity, report_id: report_id)
  end

  def alert(title:, message:, severity:, report_id: nil)
    # Telegram
    send_telegram(title, message, severity) if telegram_configured?
    
    # Slack
    send_slack(title, message, severity) if slack_configured?
    
    # Fallback: log
    log_alert(title, message, severity, report_id)
  end

  private

  def telegram_configured?
    ENV['TELEGRAM_BOT_TOKEN'].present? && ENV['TELEGRAM_CHAT_ID'].present?
  end

  def slack_configured?
    ENV['SLACK_WEBHOOK_URL'].present?
  end

  def send_telegram(title, message, severity)
    emoji = { critical: '🚨', warning: '⚠️', info: 'ℹ️' }[severity] || 'ℹ️'
    
    text = "#{emoji} *#{title}*\n\n#{message}"

    HTTParty.post(
      "https://api.telegram.org/bot#{ENV['TELEGRAM_BOT_TOKEN']}/sendMessage",
      body: {
        chat_id: ENV['TELEGRAM_CHAT_ID'],
        text: text,
        parse_mode: 'Markdown'
      }
    )
  rescue => e
    Rails.logger.error("Telegram notification failed: #{e.message}")
  end

  def send_slack(title, message, severity)
    color = { critical: 'danger', warning: 'warning', info: 'good' }[severity] || 'good'

    HTTParty.post(
      ENV['SLACK_WEBHOOK_URL'],
      headers: { 'Content-Type' => 'application/json' },
      body: {
        attachments: [{
          color: color,
          title: title,
          text: message,
          ts: Time.current.to_i
        }]
      }.to_json
    )
  rescue => e
    Rails.logger.error("Slack notification failed: #{e.message}")
  end

  def log_alert(title, message, severity, report_id)
    Rails.logger.tagged("ALERT:#{severity.upcase}") do
      Rails.logger.warn("#{title}: #{message} (report_id: #{report_id})")
    end
  end
end

### 6. Создай RateController

Создай файл `app/services/rate_controller.rb`:

class RateController
  REDIS_PREFIX = 'rate_control:'.freeze

  def self.reduce_rate(domain, factor: 0.5, duration: 1.hour)
    redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
    key = "#{REDIS_PREFIX}#{domain}"
    
    current = redis.get(key)&.to_f || 1.0
    new_rate = [current * factor, 0.1].max
    
    redis.setex(key, duration.to_i, new_rate.to_s)
    
    Rails.logger.info("RateController: Reduced rate for #{domain} to #{new_rate}")
    new_rate
  end

  def self.get_rate(domain)
    redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
    redis.get("#{REDIS_PREFIX}#{domain}")&.to_f || 1.0
  end

  def self.reset_rate(domain)
    redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
    redis.del("#{REDIS_PREFIX}#{domain}")
  end
end

### 7. Создай RetryJob

Создай файл `app/jobs/retry_scheduled_emails_job.rb`:

class RetryScheduledEmailsJob < ApplicationJob
  queue_as :default

  def perform
    EmailLog.pending_retry.find_each do |email_log|
      # Проверяем что адрес не в blacklist
      if Blacklist.blocked?(email_log.recipient)
        email_log.update!(status: 'failed', error_message: 'Recipient blacklisted')
        next
      end

      # Сбрасываем статус и перезапускаем
      email_log.update!(status: 'queued', next_retry_at: nil)
      BuildEmailJob.perform_async(email_log.id)
    end
  end
end

### 8. Создай HourlyStatsJob

Создай файл `app/jobs/hourly_stats_job.rb`:

class HourlyStatsJob < ApplicationJob
  queue_as :low

  def perform(hour = nil)
    hour ||= 1.hour.ago

    # Глобальная статистика
    HourlyStats.aggregate_hour(hour)

    # По доменам (топ-10)
    top_domains = EmailLog
      .where(created_at: hour.beginning_of_hour...(hour.beginning_of_hour + 1.hour))
      .group(:recipient_domain)
      .order('count(*) desc')
      .limit(10)
      .pluck(:recipient_domain)

    top_domains.each do |domain|
      HourlyStats.aggregate_hour(hour, domain: domain)
    end

    # Проверяем аномалии
    AnomalyDetector.check_hourly
  end
end

### 9. Добавь в Gemfile

Добавь в Gemfile перед group :development:

# HTTP клиент (уже есть)
# gem 'httparty', '~> 0.21'

# Connection pooling для Redis
gem 'connection_pool', '~> 2.4'

Запусти: bundle install

### 10. Добавь переменные в .env

Добавь в services/api/.env:

# AI Analytics
ANTHROPIC_API_KEY=

# Notifications
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=
SLACK_WEBHOOK_URL=

# CORS
ALLOWED_ORIGINS=http://localhost:3000,https://your-ams-domain.com

После всех изменений запусти миграции: bundle exec rails db:migrate
```

---

## Проверка после всех фаз

```
Проверь что всё работает:

1. Запусти rails console и выполни:
   - EmailTemplate.new.valid? # должен быть false (нет required полей)
   - Blacklist.add('test@example.com', reason: 'manual')
   - Blacklist.blocked?('test@example.com') # должен быть true
   - HourlyStats.new.valid? # проверка модели

2. Запусти тесты если есть: bundle exec rspec

3. Проверь что сервер стартует: bundle exec rails s

4. Проверь routes: bundle exec rails routes | grep api

5. Проверь миграции: bundle exec rails db:migrate:status
```

---

## Добавить в crontab

После деплоя добавь cron jobs. Создай файл `config/schedule.rb` (gem whenever):

```ruby
every 1.hour do
  runner "HourlyStatsJob.perform_now(1.hour.ago)"
end

every 5.minutes do
  runner "RetryScheduledEmailsJob.perform_now"
end

every 1.day, at: '3:00 am' do
  runner "UpdateStatsJob.perform_now"
end
```
