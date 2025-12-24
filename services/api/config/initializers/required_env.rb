# Validate required environment variables at boot
REQUIRED_ENV = {
  'SECRET_KEY_BASE' => 'Rails secret key base',
  'DATABASE_URL' => 'Database connection URL',
  'REDIS_URL' => 'Redis connection URL',
  'ENCRYPTION_PRIMARY_KEY' => 'Encryption primary key',
  'ENCRYPTION_DETERMINISTIC_KEY' => 'Encryption deterministic key',
  'ENCRYPTION_KEY_DERIVATION_SALT' => 'Encryption key derivation salt',
  'DASHBOARD_USERNAME' => 'Dashboard username',
  'DASHBOARD_PASSWORD' => 'Dashboard password',
  'POSTAL_SIGNING_KEY' => 'Postal signing key'
  # POSTAL_WEBHOOK_PUBLIC_KEY is optional - webhook verification will be skipped if not set
}.freeze

missing = REQUIRED_ENV.select { |var, _| ENV[var].blank? }

if missing.any?
  message = <<~MSG
    Missing required environment variables:
    #{missing.map { |var, desc| "  - #{var} (#{desc})" }.join("\n")}
  MSG

  if Rails.env.production?
    raise message
  elsif !Rails.env.test?
    Rails.logger.error(message)
    warn message
  end
end
