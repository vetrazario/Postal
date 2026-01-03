# frozen_string_literal: true

# Dynamic Sidekiq Web UI authentication
# Reads credentials from SystemConfig (database) or falls back to ENV
class SidekiqWebAuth
  def self.authenticate(username, password)
    # Try to get credentials from SystemConfig (database)
    config = begin
      SystemConfig.instance
    rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::StatementInvalid
      nil
    end

    if config
      expected_username = config.sidekiq_web_username.presence || ENV.fetch('SIDEKIQ_WEB_USERNAME', 'admin')
      expected_password = config.sidekiq_web_password.presence || ENV['SIDEKIQ_WEB_PASSWORD']
    else
      # Fallback to ENV if database not available
      expected_username = ENV.fetch('SIDEKIQ_WEB_USERNAME', 'admin')
      expected_password = ENV['SIDEKIQ_WEB_PASSWORD']
    end

    return false if expected_password.blank?

    # Use secure comparison to prevent timing attacks
    ActiveSupport::SecurityUtils.secure_compare(
      ::Digest::SHA256.hexdigest(username.to_s),
      ::Digest::SHA256.hexdigest(expected_username.to_s)
    ) & ActiveSupport::SecurityUtils.secure_compare(
      ::Digest::SHA256.hexdigest(password.to_s),
      ::Digest::SHA256.hexdigest(expected_password.to_s)
    )
  end

  # Check if Sidekiq Web should be enabled
  def self.enabled?
    # Check database first
    config = begin
      SystemConfig.instance
    rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::StatementInvalid
      nil
    end

    if config
      config.sidekiq_web_username.present? && config.sidekiq_web_password.present?
    else
      # Fallback to ENV
      ENV['SIDEKIQ_WEB_USERNAME'].present? && ENV['SIDEKIQ_WEB_PASSWORD'].present?
    end
  end
end
