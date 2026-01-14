# Validate required environment variables at boot

# Critical variables that MUST be set
REQUIRED_ENV = {
  'SECRET_KEY_BASE' => 'Rails secret key base',
  'DATABASE_URL' => 'Database connection URL',
  'REDIS_URL' => 'Redis connection URL',
  'ENCRYPTION_PRIMARY_KEY' => 'Encryption primary key',
  'ENCRYPTION_DETERMINISTIC_KEY' => 'Encryption deterministic key',
  'ENCRYPTION_KEY_DERIVATION_SALT' => 'Encryption key derivation salt',
  'POSTAL_SIGNING_KEY' => 'Postal signing key',
  'DOMAIN' => 'Domain name for the application'
}.freeze

# Variables required for full functionality (warning only)
RECOMMENDED_ENV = {
  'POSTAL_API_KEY' => 'Postal API key for sending emails',
  'WEBHOOK_SECRET' => 'Secret for signing webhooks',
  'AMS_CALLBACK_URL' => 'AMS callback URL for status updates',
  'DASHBOARD_USERNAME' => 'Dashboard admin username',
  'DASHBOARD_PASSWORD' => 'Dashboard admin password',
  'SMTP_RELAY_SECRET' => 'HMAC secret for SMTP relay authentication'
}.freeze

# Check required variables
missing = REQUIRED_ENV.select { |var, _| ENV[var].blank? }

if missing.any?
  message = <<~MSG
    Missing REQUIRED environment variables:
    #{missing.map { |var, desc| "  - #{var} (#{desc})" }.join("\n")}

    These variables are required for the application to start.
    Please set them in your .env file or environment.
  MSG

  if Rails.env.production?
    raise message
  elsif !Rails.env.test?
    Rails.logger.error(message)
    warn message
  end
end

# Check recommended variables (warning only)
missing_recommended = RECOMMENDED_ENV.select { |var, _| ENV[var].blank? }

if missing_recommended.any? && !Rails.env.test?
  message = <<~MSG
    Missing RECOMMENDED environment variables:
    #{missing_recommended.map { |var, desc| "  - #{var} (#{desc})" }.join("\n")}

    These variables are recommended for full functionality.
    Some features may not work without them.
  MSG

  Rails.logger.warn(message)
  warn message if Rails.env.development?
end

# Validate variable formats
VALIDATIONS = {
  'DATABASE_URL' => ->(v) { v.start_with?('postgres://') || v.start_with?('postgresql://') },
  'REDIS_URL' => ->(v) { v.start_with?('redis://') || v.start_with?('rediss://') },
  'SECRET_KEY_BASE' => ->(v) { v.length >= 64 },
  'POSTAL_SIGNING_KEY' => ->(v) { v.length >= 32 },
  'DOMAIN' => ->(v) { v.match?(/\A[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*\z/i) }
}.freeze

invalid = VALIDATIONS.select do |var, validator|
  ENV[var].present? && !validator.call(ENV[var])
end

if invalid.any?
  message = <<~MSG
    Invalid environment variable formats:
    #{invalid.keys.map { |var| "  - #{var}" }.join("\n")}
  MSG

  if Rails.env.production?
    raise message
  else
    warn message
  end
end
