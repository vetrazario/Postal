class TrackingController < ActionController::Base
  skip_before_action :verify_authenticity_token

  # Public endpoint - no authentication required

  # Handle click tracking: GET /go/:slug OR /t/c/:token
  def click
    # Extract token from params (supports both /go/slug-TOKEN and /t/c/TOKEN)
    token = extract_token_from_params

    unless token
      Rails.logger.warn "Invalid tracking URL: #{params.inspect}"
      redirect_to root_url, status: :moved_permanently
      return
    end

    click_record = EmailClick.find_by(token: token)

    if click_record
      # Validate URL FIRST (before any redirect, even for bots)
      # This prevents SSRF and open redirect attacks via bot user-agents
      unless safe_redirect_url?(click_record.url)
        Rails.logger.warn "Unsafe redirect URL blocked: #{click_record.url}, Bot: #{bot_request?}, UA: #{request.user_agent}"
        redirect_to root_url, status: :moved_permanently
        return
      end

      # Skip bot clicks (redirect without tracking)
      if bot_request?
        Rails.logger.info "Bot click detected: #{click_record.id}, UA: #{request.user_agent}"
        redirect_to click_record.url, allow_other_host: true, status: :moved_permanently
        return
      end

      # Update click info (only first click from real user)
      # Use atomic UPDATE to prevent race condition
      rows_updated = EmailClick.where(
        id: click_record.id,
        ip_address: nil  # Only update if still null (race condition prevention)
      ).update_all(
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        clicked_at: Time.current,
        updated_at: Time.current
      )

      # Only increment stats if we actually updated (were first)
      if rows_updated > 0
        update_campaign_stats(click_record.campaign_id, :clicks)
        push_to_ams_buffer(click_record.email_log, click_record.url)
        Rails.logger.info "Click tracked: #{click_record.id}, URL: #{click_record.url}, IP: #{request.remote_ip}"
      end

      # Fast redirect with caching (301 Permanent)
      # URL already validated at the top of the method
      redirect_to click_record.url, allow_other_host: true, status: :moved_permanently
    else
      # Token not found - redirect to homepage
      Rails.logger.warn "Invalid click token: #{token}"
      redirect_to root_url, status: :moved_permanently
    end
  end

  # Handle open tracking: GET /t/o/:token.gif
  def open
    # Remove .gif extension if present (Rails routing captures it)
    token = params[:token]&.gsub(/\.gif$/, '')

    # Return pixel immediately for bots (no tracking)
    if bot_request?
      send_tracking_pixel
      return
    end

    open_record = EmailOpen.find_by(token: token)

    if open_record
      # Update open info (only first open from real user)
      # Use atomic UPDATE to prevent race condition
      rows_updated = EmailOpen.where(
        id: open_record.id,
        ip_address: nil  # Only update if still null (race condition prevention)
      ).update_all(
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        opened_at: Time.current,
        updated_at: Time.current
      )

      # Only increment stats if we actually updated (were first)
      if rows_updated > 0
        update_campaign_stats(open_record.campaign_id, :opens)
        push_to_ams_buffer(open_record.email_log, 'open_trace')
        Rails.logger.info "Open tracked: #{open_record.id}, IP: #{request.remote_ip}"
      end
    else
      Rails.logger.warn "Invalid open token: #{token}"
    end

    # Return 1x1 transparent GIF with aggressive caching
    send_tracking_pixel
  end

  private

  # Extract token from various URL formats
  def extract_token_from_params
    # Format 1: /go/slug-TOKEN (new readable format)
    if params[:slug].present?
      parts = params[:slug].split('-')
      # Token is everything after last dash (16 chars for collision resistance)
      partial_token = parts.last

      if partial_token.present? && partial_token.length >= 16
        # Find full token by partial match (with SQL escaping for LIKE)
        sanitized_token = EmailClick.sanitize_sql_like(partial_token)
        click = EmailClick.where("token LIKE ?", "#{sanitized_token}%").first
        return click&.token
      end
    end

    # Format 2: /t/c/TOKEN (legacy format)
    if params[:token].present?
      return params[:token]
    end

    nil
  end

  # Detect bot requests
  def bot_request?
    ua = request.user_agent.to_s.downcase

    # Common bot patterns with word boundaries to avoid false positives
    # (e.g., "Bottle" won't match, "Robot Framework" won't match, "Checkpoint" won't match)
    bot_patterns = [
      /\bbot\b/,         # Standalone "bot" word
      /bot[\/\-_]/,      # "bot/" or "bot-" (e.g., "googlebot/", "yandexbot-")
      /crawl/,           # Matches "crawler", "webcrawler", etc.
      /spider/,          # Web spiders
      /\bslurp/,         # Yahoo Slurp
      /mediapartners/,   # Google Mediapartners
      /facebookexternalhit/,
      /twitterbot/,
      /whatsapp/,
      /googlebot/,
      /bingbot/,
      /yandexbot/,
      /\bscanner\b/,     # Security scanners
      /\bpreview\b.*\bbot/  # Link preview bots
    ]

    bot_patterns.any? { |pattern| ua.match?(pattern) }
  end

  # Send 1x1 transparent GIF
  def send_tracking_pixel
    # 1x1 transparent GIF (base64 decoded)
    pixel_data = Base64.decode64('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7')

    # Aggressive caching headers
    response.headers['Cache-Control'] = 'public, max-age=31536000, immutable'
    response.headers['Expires'] = 1.year.from_now.httpdate
    response.headers['ETag'] = Digest::MD5.hexdigest(pixel_data)

    send_data(
      pixel_data,
      type: 'image/gif',
      disposition: 'inline'
    )
  end

  def update_campaign_stats(campaign_id, metric)
    return if campaign_id.blank? || campaign_id == 'unknown'

    stats = CampaignStats.find_or_initialize_for(campaign_id)
    case metric
    when :clicks
      stats.increment_clicked
    when :opens
      stats.increment_opened
    end
  rescue StandardError => e
    Rails.logger.error "Failed to update campaign stats: #{e.message}"
  end

  # Push tracking event to Redis buffer for AMS postMailingOpenClicksData
  def push_to_ams_buffer(email_log, url)
    return unless email_log&.campaign_id.present?

    redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://redis:6379/0'))
    redis.lpush(
      "ams_open_clicks:#{email_log.campaign_id}",
      { email: email_log.recipient, url: url }.to_json
    )
    redis.expire("ams_open_clicks:#{email_log.campaign_id}", 86400)
  rescue StandardError => e
    Rails.logger.error "AMS buffer push error: #{e.message}"
  ensure
    redis&.close
  end

  # Validate URL to prevent open redirect attacks
  def safe_redirect_url?(url)
    return false if url.blank?

    begin
      uri = URI.parse(url)

      # Block dangerous schemes (defense in depth - already blocked in LinkTracker)
      scheme_lower = uri.scheme.to_s.downcase
      return false if ['javascript', 'data', 'vbscript', 'file', 'about'].include?(scheme_lower)

      # Only allow http/https schemes
      return false unless ['http', 'https'].include?(scheme_lower)

      # Block protocol-relative URLs (//evil.com)
      return false if url.start_with?('//')

      # Require valid host
      return false if uri.host.blank?

      # Block URLs with userinfo (username/password before @)
      # Example: https://user:pass@example.com or https://trusted.com@evil.com
      # This prevents authentication credential leaks and URL spoofing
      # Safe URLs like https://twitter.com/@username are NOT blocked (@ is in path, not userinfo)
      return false if uri.userinfo.present?

      true
    rescue URI::InvalidURIError
      false
    end
  end
end
