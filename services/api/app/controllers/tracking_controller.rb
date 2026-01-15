class TrackingController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!, if: :devise_controller?

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
      # Skip bot clicks
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
        Rails.logger.info "Click tracked: #{click_record.id}, URL: #{click_record.url}, IP: #{request.remote_ip}"
      end

      # Fast redirect with caching (301 Permanent)
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
end
