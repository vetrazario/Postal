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
      if click_record.ip_address.blank?
        click_record.update!(
          ip_address: request.remote_ip,
          user_agent: request.user_agent,
          clicked_at: Time.current
        )

        # Update campaign stats
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
    token = params[:token]

    # Return pixel immediately for bots (no tracking)
    if bot_request?
      send_tracking_pixel
      return
    end

    open_record = EmailOpen.find_by(token: token)

    if open_record
      # Update open info (only first open from real user)
      if open_record.ip_address.blank?
        open_record.update!(
          ip_address: request.remote_ip,
          user_agent: request.user_agent,
          opened_at: Time.current
        )

        # Update campaign stats
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
      # Token is everything after last dash (might be partial - 8 chars)
      partial_token = parts.last

      if partial_token.length >= 8
        # Find full token by partial match
        click = EmailClick.where("token LIKE ?", "#{partial_token}%").first
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

    # Common bot patterns
    bot_patterns = [
      'bot', 'crawl', 'spider', 'slurp', 'mediapartners',
      'facebookexternalhit', 'twitterbot', 'whatsapp',
      'googlebot', 'bingbot', 'yandexbot',
      'preview', 'scanner', 'check'
    ]

    bot_patterns.any? { |pattern| ua.include?(pattern) }
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
