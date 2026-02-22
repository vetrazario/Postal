class TrackingInjector
  def self.inject_tracking_links(html:, recipient:, campaign_id:, message_id:, domain:)
    return html if html.blank? || recipient.blank? || campaign_id.blank? || message_id.blank?

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

      # Rewrite amsweb.php and all other links through our tracking (hides AMS; we report back via webhook)

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
    return html if html.blank? || recipient.blank? || campaign_id.blank? || message_id.blank?

    encoded_email = Base64.urlsafe_encode64(recipient)
    encoded_cid = Base64.urlsafe_encode64(campaign_id)
    encoded_mid = Base64.urlsafe_encode64(message_id)
    
    tracking_url = "https://#{domain}/track/o?eid=#{encoded_email}&cid=#{encoded_cid}&mid=#{encoded_mid}"
    pixel_html = "<img src=\"#{tracking_url}\" width=\"1\" height=\"1\" alt=\"\" style=\"border:0;width:1px;height:1px;\" />"
    
    # Insert before </body>, or before </html> if no </body>, or at the end
    if html.include?("</body>")
      html.sub("</body>", "#{pixel_html}\n</body>")
    elsif html =~ %r{</html>}i
      html.sub(%r{</html>}i, "#{pixel_html}\n</html>")
    else
      html + pixel_html
    end
  end

  def self.inject_unsubscribe_footer(html:, recipient:, campaign_id:, domain:)
    return html if html.blank? || recipient.blank? || campaign_id.blank?

    encoded_email = Base64.urlsafe_encode64(recipient)
    encoded_cid = Base64.urlsafe_encode64(campaign_id)
    unsubscribe_url = "https://#{domain}/unsubscribe?eid=#{encoded_email}&cid=#{encoded_cid}"

    footer_html = <<~HTML
      <div style="margin-top: 30px; padding-top: 15px; border-top: 1px solid #eee; font-size: 11px; color: #999; text-align: center;">
        <p>
          <a href="#{unsubscribe_url}" style="color: #999; text-decoration: underline;">Отписаться от рассылки</a>
        </p>
      </div>
    HTML

    if html.include?("</body>")
      html.sub("</body>", "#{footer_html}</body>")
    else
      html + footer_html
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

    html = inject_unsubscribe_footer(
      html: html,
      recipient: recipient,
      campaign_id: campaign_id,
      domain: domain
    )

    html
  end
end





