class TrackingInjector
  def self.inject_tracking_links(html:, recipient:, campaign_id:, message_id:, domain:)
    return html if html.blank?
    
    encoded_email = Base64.urlsafe_encode64(recipient)
    encoded_cid = Base64.urlsafe_encode64(campaign_id)
    encoded_mid = Base64.urlsafe_encode64(message_id)
    
    # Replace all href links with tracking links
    html.gsub(/<a\s+([^>]*\s+)?href=["']([^"']+)["']([^>]*)>/i) do |match|
      attrs_before = $1 || ""
      original_url = $2
      attrs_after = $3 || ""

      # Skip links that already use tracking domain
      next match if original_url.include?(domain)

      # Skip mailto: links
      next match if original_url.start_with?("mailto:")

      # Skip anchor links
      next match if original_url.start_with?("#")

      # Skip unsubscribe links (they should already be from Send Server)
      next match if original_url.include?("unsubscribe")

      # Validate URL format (only http/https)
      begin
        uri = URI.parse(original_url)
        next match unless uri.scheme.to_s.match?(/^https?$/i)
      rescue URI::InvalidURIError
        next match
      end

      # Encode original URL
      encoded_url = Base64.urlsafe_encode64(original_url)
      
      # Build tracking URL
      tracking_url = "https://#{domain}/track/c?url=#{encoded_url}&eid=#{encoded_email}&cid=#{encoded_cid}&mid=#{encoded_mid}"
      
      # Replace href
      "<a #{attrs_before}href=\"#{tracking_url}\"#{attrs_after}>"
    end
  end

  def self.inject_tracking_pixel(html:, recipient:, campaign_id:, message_id:, domain:)
    return html if html.blank?
    
    encoded_email = Base64.urlsafe_encode64(recipient)
    encoded_cid = Base64.urlsafe_encode64(campaign_id)
    encoded_mid = Base64.urlsafe_encode64(message_id)
    
    tracking_url = "https://#{domain}/track/o?eid=#{encoded_email}&cid=#{encoded_cid}&mid=#{encoded_mid}"
    pixel_html = "<img src=\"#{tracking_url}\" width=\"1\" height=\"1\" style=\"display:none;\" alt=\"\">"
    
    # Insert before </body> or at the end
    if html.include?("</body>")
      html.gsub("</body>", "#{pixel_html}\n</body>")
    else
      html + pixel_html
    end
  end

  def self.inject_all(html:, recipient:, campaign_id:, message_id:, domain:)
    html = inject_tracking_links(
      html: html,
      recipient: recipient,
      campaign_id: campaign_id,
      message_id: message_id,
      domain: domain
    )
    
    html = inject_tracking_pixel(
      html: html,
      recipient: recipient,
      campaign_id: campaign_id,
      message_id: message_id,
      domain: domain
    )
    
    html
  end
end





