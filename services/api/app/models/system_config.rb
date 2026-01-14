# frozen_string_literal: true

class SystemConfig < ApplicationRecord
  # Encryption for sensitive data (like AiSetting)
  encrypts :ams_api_key_encrypted, deterministic: false
  encrypts :postal_api_key_encrypted, deterministic: false
  encrypts :postal_signing_key_encrypted, deterministic: false
  encrypts :postal_webhook_public_key_encrypted, deterministic: false
  encrypts :webhook_secret_encrypted, deterministic: false
  encrypts :smtp_relay_secret_encrypted, deterministic: false
  encrypts :sidekiq_web_password_encrypted, deterministic: false

  # Virtual attributes for convenience (without _encrypted suffix)
  alias_attribute :ams_api_key, :ams_api_key_encrypted
  alias_attribute :postal_api_key, :postal_api_key_encrypted
  alias_attribute :postal_signing_key, :postal_signing_key_encrypted
  alias_attribute :postal_webhook_public_key, :postal_webhook_public_key_encrypted
  alias_attribute :webhook_secret, :webhook_secret_encrypted
  alias_attribute :smtp_relay_secret, :smtp_relay_secret_encrypted
  alias_attribute :sidekiq_web_password, :sidekiq_web_password_encrypted

  # Validations
  validates :domain, presence: true,
            format: {
              with: /\A[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,}\z/i,
              message: 'must be a valid domain (example.com)'
            }

  validates :ams_callback_url,
            format: {
              with: URI::DEFAULT_PARSER.make_regexp(%w[http https]),
              message: 'must be a valid URL'
            },
            allow_blank: true

  validates :daily_limit, numericality: {
    greater_than_or_equal_to: 0,
    message: 'must be >= 0'
  }

  validates :sidekiq_concurrency, numericality: {
    greater_than: 0,
    less_than_or_equal_to: 50,
    message: 'must be between 1 and 50'
  }

  # Custom validation for allowed_sender_domains
  validate :validate_sender_domains

  def validate_sender_domains
    return if allowed_sender_domains.blank?

    domains = allowed_sender_domains.split(',').map(&:strip)
    invalid = domains.reject { |d| d =~ /\A[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,}\z/i }

    if invalid.any?
      errors.add(:allowed_sender_domains, "contains invalid domains: #{invalid.join(', ')}")
    end
  end

  # Singleton pattern (only one settings record)
  def self.instance
    first_or_create!(id: 1) do |config|
      # Load from ENV on first creation
      # Provide default fallback value if ENV is not set (must be valid domain for validation)
      config.domain = ENV.fetch('DOMAIN', 'localhost')
      config.allowed_sender_domains = ENV.fetch('ALLOWED_SENDER_DOMAINS', '')
      config.cors_origins = ENV.fetch('CORS_ORIGINS', '')

      config.ams_callback_url = ENV.fetch('AMS_CALLBACK_URL', '')
      config.ams_api_key = ENV['AMS_API_KEY']
      config.ams_api_url = ENV['AMS_API_URL']

      config.postal_api_url = ENV.fetch('POSTAL_API_URL', 'http://postal:5000')
      config.postal_api_key = ENV['POSTAL_API_KEY']
      config.postal_signing_key = ENV['POSTAL_SIGNING_KEY']
      config.postal_webhook_public_key = ENV['POSTAL_WEBHOOK_PUBLIC_KEY']

      config.daily_limit = ENV.fetch('DAILY_LIMIT', 50000).to_i
      config.sidekiq_concurrency = ENV.fetch('SIDEKIQ_CONCURRENCY', 5).to_i
      config.webhook_secret = ENV['WEBHOOK_SECRET']

      # SMTP Relay settings (credentials managed via SmtpCredential model)
      config.smtp_relay_secret = ENV['SMTP_RELAY_SECRET']
      config.smtp_relay_port = ENV.fetch('SMTP_RELAY_PORT', 2587).to_i
      config.smtp_relay_auth_required = ENV.fetch('SMTP_AUTH_REQUIRED', 'true') == 'true'
      config.smtp_relay_tls_enabled = ENV.fetch('SMTP_RELAY_TLS', 'true') == 'true'

      # Sidekiq Web UI
      config.sidekiq_web_username = ENV.fetch('SIDEKIQ_WEB_USERNAME', 'admin')
      config.sidekiq_web_password = ENV['SIDEKIQ_WEB_PASSWORD']

      # Logging
      config.log_level = ENV.fetch('LOG_LEVEL', 'info')
      config.sentry_dsn = ENV['SENTRY_DSN']

      # Let's Encrypt
      config.letsencrypt_email = ENV['LETSENCRYPT_EMAIL']
    end
  rescue ActiveRecord::RecordInvalid => e
    # If validation fails on first create, return existing record or create with defaults
    Rails.logger.error "SystemConfig validation failed: #{e.message}"
    existing = find_by(id: 1)
    return existing if existing

    # Create with safe defaults if no existing record
    create!(
      id: 1,
      domain: ENV.fetch('DOMAIN', 'localhost'),
      allowed_sender_domains: ENV.fetch('ALLOWED_SENDER_DOMAINS', ''),
      cors_origins: ENV.fetch('CORS_ORIGINS', ''),
      ams_callback_url: ENV.fetch('AMS_CALLBACK_URL', ''),
      ams_api_key: ENV['AMS_API_KEY'],
      ams_api_url: ENV['AMS_API_URL'],
      postal_api_url: ENV.fetch('POSTAL_API_URL', 'http://postal:5000'),
      postal_api_key: ENV['POSTAL_API_KEY'],
      postal_signing_key: ENV['POSTAL_SIGNING_KEY'],
      daily_limit: ENV.fetch('DAILY_LIMIT', 50000).to_i,
      sidekiq_concurrency: ENV.fetch('SIDEKIQ_CONCURRENCY', 5).to_i,
      webhook_secret: ENV['WEBHOOK_SECRET']
    )
  end

  # Test AMS connection
  def test_ams_connection
    return { success: false, error: 'AMS Callback URL not configured' } if ams_callback_url.blank?

    begin
      response = HTTParty.head(
        ams_callback_url,
        timeout: 5,
        headers: ams_api_key.present? ? { 'Authorization' => "Bearer #{ams_api_key}" } : {}
      )

      {
        success: [200, 204, 404, 405].include?(response.code), # 404/405 also OK - server is reachable
        message: "HTTP #{response.code}",
        code: response.code
      }
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      { success: false, error: "Timeout: #{e.message}" }
    rescue SocketError => e
      { success: false, error: "DNS error: #{e.message}" }
    rescue StandardError => e
      { success: false, error: e.message }
    end
  end

  # Test Postal connection
  def test_postal_connection
    return { success: false, error: 'Postal API URL not configured' } if postal_api_url.blank?

    # Check if API key looks like a placeholder
    if postal_api_key.blank?
      return { success: false, error: 'Postal API Key not configured' }
    elsif postal_api_key.include?('your_') || postal_api_key.include?('CHANGE_ME')
      return { success: false, error: 'Postal API Key is a placeholder - set real key from Postal admin' }
    end

    begin
      Rails.logger.info "Testing Postal connection: #{postal_api_url}"

      # Get first allowed domain or use domain field
      test_domain = allowed_sender_domains.to_s.split(',').first&.strip || domain || 'example.com'

      # Send minimal valid test message to verify connectivity
      response = HTTParty.post(
        "#{postal_api_url}/api/v1/send/message",
        timeout: 5,
        headers: {
          'Host' => test_domain,
          'X-Server-API-Key' => postal_api_key,
          'Content-Type' => 'application/json'
        },
        body: {
          to: ["test@#{test_domain}"],
          from: "noreply@#{test_domain}",
          subject: 'Connection test',
          plain_body: 'Test connection'
        }.to_json
      )

      Rails.logger.info "Postal response: code=#{response.code}, body=#{response.body[0..200]}"

      # 200 = message sent/queued OK, 401/403 = auth failed
      if [200, 201].include?(response.code)
        { success: true, message: "Connected successfully (HTTP #{response.code})", code: response.code }
      elsif [401, 403].include?(response.code)
        { success: false, error: "Authentication failed (HTTP #{response.code}) - check API key", code: response.code }
      else
        { success: false, error: "Unexpected response: HTTP #{response.code}", code: response.code, body: response.body[0..200] }
      end
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      Rails.logger.error "Postal timeout: #{e.message}"
      { success: false, error: "Timeout: #{e.message}" }
    rescue SocketError => e
      Rails.logger.error "Postal DNS error: #{e.message}"
      { success: false, error: "DNS error: #{e.message}" }
    rescue Errno::ECONNREFUSED => e
      Rails.logger.error "Postal connection refused: #{e.message}"
      { success: false, error: "Connection refused - is Postal running?" }
    rescue StandardError => e
      Rails.logger.error "Postal test error: #{e.class} - #{e.message}\n#{e.backtrace.first(3).join("\n")}"
      { success: false, error: "#{e.class}: #{e.message}" }
    end
  end

  # Fields that affect which services
  FIELD_AFFECTS = {
    domain: ['api', 'sidekiq', 'postal'],
    allowed_sender_domains: ['api'],
    cors_origins: ['api'],

    ams_callback_url: ['api', 'sidekiq'],
    ams_api_key: ['sidekiq'],
    ams_api_url: ['sidekiq'],

    postal_api_url: ['api', 'sidekiq'],
    postal_api_key: ['api', 'sidekiq'],
    postal_signing_key: ['api'],
    postal_webhook_public_key: ['api'],

    daily_limit: ['api'],
    sidekiq_concurrency: ['sidekiq'],
    webhook_secret: ['api'],

    # SMTP Relay settings (credentials managed via SmtpCredential)
    smtp_relay_secret: ['smtp-relay', 'api'],
    smtp_relay_port: ['smtp-relay'],
    smtp_relay_auth_required: ['smtp-relay'],
    smtp_relay_tls_enabled: ['smtp-relay'],

    # Sidekiq Web UI
    sidekiq_web_username: ['api'],
    sidekiq_web_password: ['api'],

    # Logging
    log_level: ['api', 'sidekiq'],
    sentry_dsn: ['api', 'sidekiq'],

    # Let's Encrypt
    letsencrypt_email: []
  }.freeze

  # After save - determine which services require restart
  after_save :mark_restart_required

  def mark_restart_required
    affected = []

    saved_changes.keys.each do |field|
      field_sym = field.to_sym
      if FIELD_AFFECTS[field_sym]
        affected += FIELD_AFFECTS[field_sym]
      end
    end

    if affected.any?
      update_columns(
        restart_required: true,
        restart_services: affected.uniq,
        changed_fields: saved_changes.except('updated_at', 'changed_fields', 'restart_required', 'restart_services')
      )
    end
  end

  # Sync to .env file
  def sync_to_env_file(env_path = Rails.root.join('.env'))
    env_content = []

    # Header
    env_content << "# Generated automatically from SystemConfig"
    env_content << "# Date: #{Time.current}"
    env_content << ""

    # Server
    env_content << "# Server Configuration"
    env_content << "DOMAIN=#{domain}"
    env_content << "ALLOWED_SENDER_DOMAINS=#{allowed_sender_domains}" if allowed_sender_domains.present?
    env_content << "CORS_ORIGINS=#{cors_origins}" if cors_origins.present?
    env_content << ""

    # AMS
    env_content << "# AMS Integration"
    env_content << "AMS_CALLBACK_URL=#{ams_callback_url}"
    env_content << "AMS_API_KEY=#{ams_api_key}" if ams_api_key.present?
    env_content << "AMS_API_URL=#{ams_api_url}" if ams_api_url.present?
    env_content << ""

    # Postal
    env_content << "# Postal"
    env_content << "POSTAL_API_URL=#{postal_api_url}"
    env_content << "POSTAL_API_KEY=#{postal_api_key}" if postal_api_key.present?
    env_content << "POSTAL_SIGNING_KEY=#{postal_signing_key}" if postal_signing_key.present?
    env_content << "POSTAL_WEBHOOK_PUBLIC_KEY=#{postal_webhook_public_key.to_s.gsub("\n", '\\n')}" if postal_webhook_public_key.present?
    env_content << ""

    # Limits
    env_content << "# Limits & Security"
    env_content << "DAILY_LIMIT=#{daily_limit}"
    env_content << "SIDEKIQ_CONCURRENCY=#{sidekiq_concurrency}"
    env_content << "WEBHOOK_SECRET=#{webhook_secret}" if webhook_secret.present?
    env_content << ""

    # SMTP Relay (credentials managed via SmtpCredential model in Dashboard)
    env_content << "# SMTP Relay"
    env_content << "SMTP_RELAY_SECRET=#{smtp_relay_secret}" if smtp_relay_secret.present?
    env_content << "SMTP_RELAY_PORT=#{smtp_relay_port}"
    env_content << "SMTP_AUTH_REQUIRED=#{smtp_relay_auth_required}"
    env_content << "SMTP_RELAY_TLS=#{smtp_relay_tls_enabled}"
    env_content << ""

    # Sidekiq Web UI
    env_content << "# Sidekiq Web UI"
    env_content << "SIDEKIQ_WEB_USERNAME=#{sidekiq_web_username}" if sidekiq_web_username.present?
    env_content << "SIDEKIQ_WEB_PASSWORD=#{sidekiq_web_password}" if sidekiq_web_password.present?
    env_content << ""

    # Logging
    env_content << "# Logging"
    env_content << "LOG_LEVEL=#{log_level}" if log_level.present?
    env_content << "SENTRY_DSN=#{sentry_dsn}" if sentry_dsn.present?
    env_content << ""

    # Let's Encrypt
    env_content << "# Let's Encrypt"
    env_content << "LETSENCRYPT_EMAIL=#{letsencrypt_email}" if letsencrypt_email.present?

    File.write(env_path, env_content.join("\n"))
    Rails.logger.info "✅ Synced configuration to #{env_path}"

    true
  rescue StandardError => e
    Rails.logger.error "❌ Failed to sync to .env: #{e.message}"
    false
  end

  # Test SMTP Relay connection (check if service is reachable)
  def test_smtp_relay_connection
    require 'socket'
    require 'timeout'

    smtp_host = 'smtp-relay'
    smtp_port_to_test = smtp_relay_port || 2587

    begin
      Timeout.timeout(5) do
        socket = TCPSocket.new(smtp_host, smtp_port_to_test)
        banner = socket.gets
        socket.close

        if banner&.start_with?('220')
          { success: true, message: "SMTP Relay is running", banner: banner.strip }
        else
          { success: false, error: "Unexpected response: #{banner&.strip}" }
        end
      end
    rescue Timeout::Error
      { success: false, error: 'Connection timeout - SMTP Relay not responding' }
    rescue Errno::ECONNREFUSED
      { success: false, error: 'Connection refused - SMTP Relay not running' }
    rescue SocketError => e
      { success: false, error: "DNS error: #{e.message}" }
    rescue StandardError => e
      { success: false, error: "#{e.class}: #{e.message}" }
    end
  end

  # Get SMTP Relay config as hash (for API endpoint)
  def smtp_relay_config
    {
      secret: smtp_relay_secret,
      port: smtp_relay_port,
      auth_required: smtp_relay_auth_required,
      tls_enabled: smtp_relay_tls_enabled,
      domain: domain
    }
  end

  # Get configuration value (for use in code)
  def self.get(key)
    instance.send(key)
  rescue NoMethodError
    nil
  end
end
