class LinkTracker
  attr_reader :email_log, :domain, :options

  DEFAULT_OPTIONS = {
    track_clicks: true,
    track_opens: false,
    use_utm: true,
    max_tracked_links: 5,
    branded_domain: nil,
    add_footer: true
  }.freeze

  def initialize(email_log:, domain: nil, **options)
    @email_log = email_log
    @domain = domain || SystemConfig.get(:domain) || 'localhost'
    @options = DEFAULT_OPTIONS.merge(load_system_defaults).merge(options)
  end

  # Replace all links in HTML with tracking URLs
  def track_links(html_body)
    return html_body if html_body.blank? || !options[:track_clicks]

    doc = Nokogiri::HTML.fragment(html_body)
    tracked_count = 0

    # Track all <a href="..."> links
    doc.css('a[href]').each do |link|
      original_url = link['href']
      next if original_url.blank?
      next if original_url.start_with?('#', 'mailto:', 'tel:') # Skip anchors, mailto, tel

      # Limit number of tracked links (track only important CTAs)
      break if tracked_count >= options[:max_tracked_links]

      tracking_url = create_tracking_url(original_url)
      link['href'] = tracking_url
      tracked_count += 1
    end

    doc.to_html
  end

  # Add tracking pixel to HTML
  def add_tracking_pixel(html_body)
    return html_body if html_body.blank? || !options[:track_opens]

    token = EmailOpen.generate_token
    pixel_url = "https://#{domain}/t/o/#{token}.gif"

    # Create tracking record (will be updated when opened)
    EmailOpen.create!(
      email_log: email_log,
      campaign_id: email_log.campaign_id || 'unknown',
      token: token,
      opened_at: Time.current
    )

    # Insert pixel before </body> or at end
    pixel_tag = %(<img src="#{pixel_url}" width="1" height="1" alt="" style="display:none;" />)

    if html_body.include?('</body>')
      html_body.sub('</body>', "#{pixel_tag}</body>")
    else
      html_body + pixel_tag
    end
  end

  # Add privacy footer
  def add_footer(html_body)
    return html_body unless options[:add_footer]
    return html_body if html_body.blank?

    footer_html = <<~HTML
      <div style="margin-top: 40px; padding-top: 20px; border-top: 1px solid #eee; font-size: 11px; color: #999; text-align: center;">
        <p>
          Мы используем аналитику для улучшения качества наших писем.
          <a href="https://#{domain}/privacy" style="color: #999; text-decoration: underline;">Политика конфиденциальности</a>
        </p>
      </div>
    HTML

    if html_body.include?('</body>')
      html_body.sub('</body>', "#{footer_html}</body>")
    else
      html_body + footer_html
    end
  end

  # Process HTML: track links + add pixel + footer
  def process_html(html_body, track_clicks: nil, track_opens: nil)
    # Override options if explicitly provided
    opts = options.dup
    opts[:track_clicks] = track_clicks unless track_clicks.nil?
    opts[:track_opens] = track_opens unless track_opens.nil?

    @options = opts

    result = html_body
    result = track_links(result) if opts[:track_clicks]
    result = add_tracking_pixel(result) if opts[:track_opens]
    result = add_footer(result) if opts[:add_footer]
    result
  end

  private

  def load_system_defaults
    {
      track_clicks: SystemConfig.get(:enable_click_tracking) || true,
      track_opens: SystemConfig.get(:enable_open_tracking) || false,
      use_utm: SystemConfig.get(:use_utm_tracking) || true,
      max_tracked_links: SystemConfig.get(:max_tracked_links) || 5,
      branded_domain: SystemConfig.get(:tracking_domain),
      add_footer: SystemConfig.get(:tracking_footer_enabled) || true
    }
  end

  def create_tracking_url(original_url)
    if options[:use_utm] && can_use_utm?(original_url)
      create_utm_url(original_url)
    else
      create_redirect_url(original_url)
    end
  end

  # UTM-based tracking (Gmail-friendly, no redirect)
  def create_utm_url(original_url)
    token = EmailClick.generate_token

    # Store click record
    EmailClick.create!(
      email_log: email_log,
      campaign_id: email_log.campaign_id || 'unknown',
      url: original_url,
      token: token,
      clicked_at: Time.current
    )

    # Add UTM parameters
    uri = URI.parse(original_url)
    params = URI.decode_www_form(uri.query || '')

    # Add UTM tracking
    params << ['utm_source', 'email']
    params << ['utm_medium', 'campaign']
    params << ['utm_campaign', email_log.campaign_id] if email_log.campaign_id
    params << ['_t', token] # Hidden tracking token for server-side logging

    uri.query = URI.encode_www_form(params)
    uri.to_s
  rescue URI::InvalidURIError => e
    Rails.logger.error "Invalid URL for UTM tracking: #{original_url}, error: #{e.message}"
    original_url # Return original if can't parse
  end

  # Redirect-based tracking (for external links or when UTM not suitable)
  def create_redirect_url(original_url)
    token = EmailClick.generate_token

    # Store click record
    EmailClick.create!(
      email_log: email_log,
      campaign_id: email_log.campaign_id || 'unknown',
      url: original_url,
      token: token,
      clicked_at: Time.current
    )

    # Use branded domain if configured, otherwise main domain
    tracking_host = options[:branded_domain] || domain

    "https://#{tracking_host}/t/c/#{token}"
  end

  # Check if URL can use UTM parameters (own site or allows query params)
  def can_use_utm?(url)
    uri = URI.parse(url)

    # Don't use UTM for URLs that look like API endpoints or have tokens
    return false if url.include?('/api/')
    return false if url.include?('token=')
    return false if url.include?('key=')

    # Safe to use UTM for most websites
    true
  rescue URI::InvalidURIError
    false
  end
end
