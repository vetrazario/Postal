require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module EmailSenderApi
  class Application < Rails::Application
    config.load_defaults 7.1

    # API-only mode (but allow HTML views for dashboard)
    config.api_only = false
    
    # Add ActionView for HTML rendering (dashboard)
    # config.action_view.raise_on_missing_translations = true # Deprecated in Rails 7.1
    
    # Add view paths
    config.paths.add "app/views", eager_load: true

    # Timezone
    config.time_zone = 'UTC'
    config.active_record.default_timezone = :utc

    # Encryption keys for PII data
    config.active_record.encryption.primary_key = ENV.fetch("ENCRYPTION_PRIMARY_KEY")
    config.active_record.encryption.deterministic_key = ENV.fetch("ENCRYPTION_DETERMINISTIC_KEY")
    config.active_record.encryption.key_derivation_salt = ENV.fetch("ENCRYPTION_KEY_DERIVATION_SALT")

    # CORS
    cors_origins = ENV.fetch('CORS_ORIGINS', '').split(',').map(&:strip).reject(&:blank?)
    
    # В development/test разрешаем * по умолчанию, если не задано
    if Rails.env.development? || Rails.env.test?
      cors_origins = ['*'] if cors_origins.empty?
    end
    
    # В production требуем явного указания origins
    if cors_origins.any?
      config.middleware.insert_before 0, Rack::Cors do
        allow do
          origins cors_origins
          resource '/api/*',
            headers: :any,
            methods: [:get, :post, :put, :patch, :delete, :options, :head],
            credentials: false
        end
      end
    elsif Rails.env.production?
      Rails.logger.warn("CORS_ORIGINS not set in production - CORS disabled")
    end


    # Logging
    config.log_level = ENV.fetch("LOG_LEVEL", "info").to_sym
  end
end

