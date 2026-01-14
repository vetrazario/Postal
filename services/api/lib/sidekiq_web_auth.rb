# frozen_string_literal: true

# Dynamic Sidekiq Web UI authentication
# Reads credentials from SystemConfig (database) or falls back to ENV
class SidekiqWebAuth
  def self.authenticate(username, password)
    # Try to get credentials from SystemConfig (database)
    config = begin
      SystemConfig.instance
    rescue StandardError
      # Database not available, connection error, or any other issue
      nil
    end

    if config
      db_username = config.sidekiq_web_username
      db_password = config.sidekiq_web_password
      expected_username = (db_username.nil? || db_username.empty?) ? ENV.fetch('SIDEKIQ_WEB_USERNAME', 'admin') : db_username
      expected_password = (db_password.nil? || db_password.empty?) ? ENV['SIDEKIQ_WEB_PASSWORD'] : db_password
    else
      # Fallback to ENV if database not available
      expected_username = ENV.fetch('SIDEKIQ_WEB_USERNAME', 'admin')
      expected_password = ENV['SIDEKIQ_WEB_PASSWORD']
    end

    # Return false if no password configured
    return false if expected_password.nil? || expected_password.empty?

    # Use secure comparison to prevent timing attacks
    username_match = secure_compare(username.to_s, expected_username.to_s)
    password_match = secure_compare(password.to_s, expected_password.to_s)

    username_match && password_match
  end

  # Check if Sidekiq Web should be enabled
  def self.enabled?
    # Check database first
    config = begin
      SystemConfig.instance
    rescue StandardError
      nil
    end

    if config
      db_username = config.sidekiq_web_username
      db_password = config.sidekiq_web_password
      !(db_username.nil? || db_username.empty?) && !(db_password.nil? || db_password.empty?)
    else
      # Fallback to ENV
      env_username = ENV['SIDEKIQ_WEB_USERNAME']
      env_password = ENV['SIDEKIQ_WEB_PASSWORD']
      !(env_username.nil? || env_username.empty?) && !(env_password.nil? || env_password.empty?)
    end
  end

  private

  def self.secure_compare(a, b)
    return false if a.nil? || b.nil?

    # Use ActiveSupport if available, otherwise use constant-time comparison
    if defined?(ActiveSupport::SecurityUtils)
      ActiveSupport::SecurityUtils.secure_compare(
        ::Digest::SHA256.hexdigest(a),
        ::Digest::SHA256.hexdigest(b)
      )
    else
      # Fallback to OpenSSL's secure comparison
      require 'openssl'
      a_hash = ::Digest::SHA256.hexdigest(a)
      b_hash = ::Digest::SHA256.hexdigest(b)
      OpenSSL.secure_compare(a_hash, b_hash)
    end
  end
end
