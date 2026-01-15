class LinkTracker
  attr_reader :email_log, :domain

  def initialize(email_log:, domain: nil)
    @email_log = email_log
    @domain = domain || SystemConfig.get(:domain) || 'localhost'
  end

  # Replace all links in HTML with tracking URLs
  def track_links(html_body)
    return html_body if html_body.blank?

    doc = Nokogiri::HTML.fragment(html_body)

    # Track all <a href="..."> links
    doc.css('a[href]').each do |link|
      original_url = link['href']
      next if original_url.blank?
      next if original_url.start_with?('#') # Skip anchors
      next if original_url.start_with?('mailto:') # Skip mailto

      tracking_url = create_tracking_url(original_url)
      link['href'] = tracking_url
    end

    doc.to_html
  end

  # Add tracking pixel to HTML
  def add_tracking_pixel(html_body)
    return html_body if html_body.blank?

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

  # Process HTML: track links + add pixel
  def process_html(html_body, track_clicks: true, track_opens: true)
    result = html_body
    result = track_links(result) if track_clicks
    result = add_tracking_pixel(result) if track_opens
    result
  end

  private

  def create_tracking_url(original_url)
    token = EmailClick.generate_token

    # Store click record (will be updated when clicked)
    EmailClick.create!(
      email_log: email_log,
      campaign_id: email_log.campaign_id || 'unknown',
      url: original_url,
      token: token,
      clicked_at: Time.current
    )

    "https://#{domain}/t/c/#{token}"
  end
end
