# frozen_string_literal: true

class SystemConfig < ApplicationRecord
  # Encryption for sensitive data (like AiSetting)
  encrypts :ams_api_key_encrypted, deterministic: false
  encrypts :postal_api_key_encrypted, deterministic: false
  encrypts :postal_signing_key_encrypted, deterministic: false
  encrypts :webhook_secret_encrypted, deterministic: false

  # Virtual attributes for convenience (without _encrypted suffix)
  alias_attribute :ams_api_key, :ams_api_key_encrypted
  alias_attribute :postal_api_key, :postal_api_key_encrypted
  alias_attribute :postal_signing_key, :postal_signing_key_encrypted
  alias_attribute :webhook_secret, :webhook_secret_encrypted

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
      config.domain = ENV.fetch('DOMAIN', '')
      config.allowed_sender_domains = ENV.fetch('ALLOWED_SENDER_DOMAINS', '')
      config.cors_origins = ENV.fetch('CORS_ORIGINS', '')

      config.ams_callback_url = ENV.fetch('AMS_CALLBACK_URL', '')
      config.ams_api_key = ENV['AMS_API_KEY']
      config.ams_api_url = ENV['AMS_API_URL']

      config.postal_api_url = ENV.fetch('POSTAL_API_URL', 'http://postal:5000')
      config.postal_api_key = ENV['POSTAL_API_KEY']
      config.postal_signing_key = ENV['POSTAL_SIGNING_KEY']

      config.daily_limit = ENV.fetch('DAILY_LIMIT', 50000).to_i
      config.sidekiq_concurrency = ENV.fetch('SIDEKIQ_CONCURRENCY', 5).to_i
      config.webhook_secret = ENV['WEBHOOK_SECRET']
    end
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
    return { success: false, error: 'Postal API Key not configured' } if postal_api_key.blank?

    begin
      # Try to get server info
      response = HTTParty.get(
        "#{postal_api_url}/api/v1/send/message",
        timeout: 5,
        headers: {
          'X-Server-API-Key' => postal_api_key,
          'Content-Type' => 'application/json'
        }
      )

      # Postal will return 400 if no data, but that means connection is OK
      {
        success: [200, 400, 401, 403].include?(response.code),
        message: "HTTP #{response.code}",
        code: response.code
      }
    rescue StandardError => e
      { success: false, error: e.message }
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

    daily_limit: ['api'],
    sidekiq_concurrency: ['sidekiq'],
    webhook_secret: ['api']
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
    env_content << ""

    # Limits
    env_content << "# Limits & Security"
    env_content << "DAILY_LIMIT=#{daily_limit}"
    env_content << "SIDEKIQ_CONCURRENCY=#{sidekiq_concurrency}"
    env_content << "WEBHOOK_SECRET=#{webhook_secret}" if webhook_secret.present?

    File.write(env_path, env_content.join("\n"))
    Rails.logger.info "✅ Synced configuration to #{env_path}"

    true
  rescue => e
    Rails.logger.error "❌ Failed to sync to .env: #{e.message}"
    false
  end

  # Get configuration value (for use in code)
  def self.get(key)
    instance.send(key)
  rescue NoMethodError
    nil
  end
end
