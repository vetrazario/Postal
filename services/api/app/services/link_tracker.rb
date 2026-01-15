class LinkTracker
  attr_reader :email_log, :domain, :options

  DEFAULT_OPTIONS = {
    track_clicks: true,
    track_opens: false,
    max_tracked_links: 10, # Увеличил - track все ссылки
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
      next if own_domain_link?(original_url) # Skip own domain links

      # Limit number of tracked links if configured
      break if tracked_count >= options[:max_tracked_links]

      tracking_url = create_tracking_url(original_url)
      link['href'] = tracking_url
      tracked_count += 1
    end

    doc.to_html
  end

  # Add tracking pixel to HTML (Gmail-optimized)
  def add_tracking_pixel(html_body)
    return html_body if html_body.blank? || !options[:track_opens]

    token = EmailOpen.generate_token
    tracking_host = options[:branded_domain] || domain
    pixel_url = "https://#{tracking_host}/t/o/#{token}.gif"

    # Create tracking record (opened_at будет установлен при загрузке пикселя)
    EmailOpen.create!(
      email_log: email_log,
      campaign_id: email_log.campaign_id || 'unknown',
      token: token
      # opened_at: nil - заполнится в TrackingController при первом открытии
    )

    # Gmail-friendly pixel: lazy loading, minimal size, no display
    pixel_tag = %(<img src="#{pixel_url}" width="1" height="1" alt="" loading="lazy" style="position:absolute;opacity:0;pointer-events:none;" />)

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
          Это письмо содержит аналитику для улучшения качества рассылок.
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

  # Check if URL belongs to our own domain (skip tracking for internal links)
  def own_domain_link?(url)
    return false if url.blank?

    begin
      uri = URI.parse(url)
      # Check if URL is from our domain or tracking domain
      return true if uri.host == domain
      return true if uri.host == options[:branded_domain]
      false
    rescue URI::InvalidURIError
      false
    end
  end

  def load_system_defaults
    {
      track_clicks: SystemConfig.get(:enable_click_tracking) != false,
      track_opens: SystemConfig.get(:enable_open_tracking) == true,
      max_tracked_links: SystemConfig.get(:max_tracked_links) || 10,
      branded_domain: SystemConfig.get(:tracking_domain),
      add_footer: SystemConfig.get(:tracking_footer_enabled) != false
    }
  end

  def create_tracking_url(original_url)
    token = EmailClick.generate_token
    slug = generate_readable_slug(original_url)

    # Store click record (clicked_at будет установлен при первом клике)
    EmailClick.create!(
      email_log: email_log,
      campaign_id: email_log.campaign_id || 'unknown',
      url: original_url,
      token: token
      # clicked_at: nil - заполнится в TrackingController при первом клике
    )

    # Use branded domain if configured, otherwise main domain
    tracking_host = options[:branded_domain] || domain

    # Create readable URL: /go/youtube-video-TOKEN instead of /t/c/TOKEN
    "https://#{tracking_host}/go/#{slug}-#{token[0..7]}"
  end

  # Generate human-readable slug from URL
  def generate_readable_slug(url)
    uri = URI.parse(url)

    # Extract meaningful parts
    domain_parts = uri.host.to_s.split('.')
    domain_name = domain_parts[-2] || 'link' # e.g., 'youtube' from youtube.com

    # Try to get meaningful path
    path_slug = uri.path.to_s
      .split('/')
      .reject(&:blank?)
      .first || 'page'

    # Clean and limit length
    slug = "#{domain_name}-#{path_slug}"
      .downcase
      .gsub(/[^a-z0-9-]/, '-')
      .gsub(/-+/, '-')
      .gsub(/^-|-$/, '')
      .slice(0, 30)

    slug.presence || 'link'
  rescue URI::InvalidURIError
    'link'
  end
end
