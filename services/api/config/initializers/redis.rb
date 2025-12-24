# Redis configuration
if Rails.env.test?
  Rails.cache = ActiveSupport::Cache::MemoryStore.new
else
  Rails.cache = ActiveSupport::Cache::RedisCacheStore.new(
    url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'),
    namespace: 'email_sender',
    expires_in: 1.hour,
    pool_size: 5,
    pool_timeout: 5
  )
end
