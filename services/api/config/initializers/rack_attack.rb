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

  # Helper to extract API key hash from request
  def self.api_key_identifier(req)
    auth_header = req.env['HTTP_AUTHORIZATION']
    return nil unless auth_header&.start_with?('Bearer ')

    token = auth_header.split(' ', 2).last
    return nil if token.blank?

    # Return hashed token as identifier (don't store raw tokens in cache)
    Digest::SHA256.hexdigest(token)[0..16]
  end

  # Safelist health check
  safelist('health') { |req| req.path == '/api/v1/health' && req.get? }

  # Safelist internal tracking events
  safelist('internal') { |req| req.path.start_with?('/api/v1/internal/') }

  # ===== IP-based throttling =====

  # Throttle send/batch: 100 req/min per IP
  throttle('api/send/ip', limit: 100, period: 1.minute) do |req|
    req.ip if req.post? && req.path.in?(['/api/v1/send', '/api/v1/batch'])
  end

  # Throttle auth attempts: 10/min per IP (brute force protection); 500 in test for faster specs
  auth_limit = Rails.env.test? ? 500 : 10
  throttle('api/auth/ip', limit: auth_limit, period: 1.minute) do |req|
    next unless req.path.start_with?('/api/') && !req.path.start_with?('/api/v1/health')
    req.ip if req.env['HTTP_AUTHORIZATION'].present?
  end

  # General API throttle: 300 req/min per IP
  throttle('api/general/ip', limit: 300, period: 1.minute) do |req|
    req.ip if req.path.start_with?('/api/')
  end

  # ===== API Key-based throttling =====

  # Throttle send/batch: 1000 req/min per API key
  throttle('api/send/key', limit: 1000, period: 1.minute) do |req|
    next unless req.post? && req.path.in?(['/api/v1/send', '/api/v1/batch'])
    api_key_identifier(req)
  end

  # Throttle batch specifically: 50 batch requests/min per API key
  throttle('api/batch/key', limit: 50, period: 1.minute) do |req|
    next unless req.post? && req.path == '/api/v1/batch'
    api_key_identifier(req)
  end

  # Daily limit per API key: 50000 requests/day
  throttle('api/daily/key', limit: 50_000, period: 1.day) do |req|
    next unless req.path.start_with?('/api/')
    api_key_identifier(req)
  end

  # ===== Dashboard throttling =====

  # Dashboard login attempts: 5/min per IP
  throttle('dashboard/login', limit: 5, period: 1.minute) do |req|
    req.ip if req.path.start_with?('/dashboard') && req.post?
  end

  # ===== Blocklist suspicious IPs =====

  # Block IPs that have made too many failed auth attempts
  blocklist('fail2ban') do |req|
    # Block for 1 hour if > 20 failed requests in last 5 minutes
    Rack::Attack::Allow2Ban.filter(req.ip, maxretry: 20, findtime: 5.minutes, bantime: 1.hour) do
      # Track failed auth attempts (set by ApplicationController)
      req.env['rack.attack.failed_auth']
    end
  end

  # Response for throttled requests
  self.throttled_responder = lambda do |req|
    match_data = req.env['rack.attack.match_data'] || {}
    retry_after = match_data[:period] || 60
    limit = match_data[:limit]
    count = match_data[:count]

    headers = {
      'Content-Type' => 'application/json',
      'Retry-After' => retry_after.to_s,
      'X-RateLimit-Limit' => limit.to_s,
      'X-RateLimit-Remaining' => '0',
      'X-RateLimit-Reset' => (Time.now + retry_after).to_i.to_s
    }

    body = {
      error: {
        code: 'rate_limit_exceeded',
        message: 'Too many requests',
        retry_after: retry_after,
        limit: limit,
        count: count
      }
    }

    [429, headers, [body.to_json]]
  end

  # Response for blocked requests
  self.blocklisted_responder = lambda do |req|
    [403, { 'Content-Type' => 'application/json' },
     [{ error: { code: 'blocked', message: 'Access denied. IP temporarily blocked.' } }.to_json]]
  end
end
