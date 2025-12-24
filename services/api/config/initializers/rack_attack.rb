# Rate limiting configuration
class Rack::Attack
  # Cache store
  cache.store = if Rails.env.test?
    ActiveSupport::Cache::MemoryStore.new
  else
    begin
      ActiveSupport::Cache::RedisCacheStore.new(
        url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')
      )
    rescue StandardError
      ActiveSupport::Cache::MemoryStore.new
    end
  end

  # Safelist health check
  safelist('health') { |req| req.path == '/api/v1/health' && req.get? }

  # Throttle send/batch: 100 req/min per IP
  throttle('api/send', limit: 100, period: 1.minute) do |req|
    req.ip if req.post? && req.path.in?(['/api/v1/send', '/api/v1/batch'])
  end

  # Throttle auth attempts: 10/min per IP
  throttle('api/auth', limit: 10, period: 1.minute) do |req|
    next unless req.path.start_with?('/api/') && !req.path.start_with?('/api/v1/health')
    req.ip if req.env['HTTP_AUTHORIZATION'].present?
  end

  # Response for throttled requests
  self.throttled_responder = lambda do |req|
    retry_after = (req.env['rack.attack.match_data'] || {})[:period] || 60
    [429, { 'Content-Type' => 'application/json', 'Retry-After' => retry_after.to_s },
     [{ error: { code: 'rate_limit_exceeded', message: 'Too many requests', retry_after: retry_after } }.to_json]]
  end

  # Response for blocked requests
  self.blocklisted_responder = lambda do |_req|
    [403, { 'Content-Type' => 'application/json' },
     [{ error: { code: 'blocked', message: 'Access denied' } }.to_json]]
  end
end
