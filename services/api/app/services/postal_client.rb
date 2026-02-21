require 'base64'

class PostalClient
  def initialize(api_url:, api_key:)
    @api_url = api_url
    @api_key = api_key
  end

  def send_message(to:, from:, subject:, html_body:, headers: {}, tag: nil, campaign_id: nil, track_clicks: true, track_opens: true)
    domain = SystemConfig.get(:domain) || 'localhost'
    message_headers = build_headers(from, to, subject, domain, campaign_id).merge(headers)

    # Log request (without sensitive data)
    Rails.logger.info "PostalClient: Sending to #{@api_url}/api/v1/send/message, recipient: #{mask_email(to)}"

    request_options = {
      headers: {
        'Host' => domain,
        'X-Server-API-Key' => @api_key,
        'Content-Type' => 'application/json'
      },
      body: {
        to: [to],
        from: from,
        sender: from,
        subject: subject,
        html_body: html_body,
        plain_body: html_to_text(html_body),
        headers: message_headers,
        tag: tag,
        bounce: true,
        track_clicks: track_clicks,
        track_opens: track_opens
      }.to_json,
      timeout: 30
    }

    # Debug output disabled in production to prevent credential leaks
    # In development, enable with DEBUG_HTTP=true (credentials will still be visible!)
    if Rails.env.development? && ENV['DEBUG_HTTP'] == 'true'
      request_options[:debug_output] = $stderr
    end

    response = HTTParty.post("#{@api_url}/api/v1/send/message", request_options)
    parse_response(response, to)
  rescue StandardError => e
    Rails.logger.error "PostalClient error: #{e.class} - #{e.message}"
    { success: false, error: e.message }
  end

  # Mask email for safe logging
  def mask_email(email)
    return email unless email&.include?('@')
    local, domain = email.split('@')
    "#{local[0]}***@#{domain}"
  end

  private

  def build_headers(from, to, subject, domain, campaign_id = nil)
    encoded_email = Base64.urlsafe_encode64(to)
    headers = {
      'From' => from,
      'To' => to,
      'Subject' => subject,
      'Message-ID' => MessageIdGenerator.generate,
      'Date' => Time.current.rfc2822,
      'MIME-Version' => '1.0',
      'Reply-To' => from,
      'X-Entity-Ref-ID' => SecureRandom.uuid,
      'Auto-Submitted' => 'auto-generated',
      'X-Auto-Response-Suppress' => 'OOF, AutoReply'
    }

    if campaign_id.present?
      encoded_cid = Base64.urlsafe_encode64(campaign_id)
      unsub_https = "https://#{domain}/unsubscribe?eid=#{encoded_email}&cid=#{encoded_cid}"
      unsub_mailto = "mailto:unsubscribe@#{domain}?subject=unsubscribe-#{encoded_cid}"

      headers['List-Unsubscribe'] = "<#{unsub_https}>, <#{unsub_mailto}>"
      headers['List-Unsubscribe-Post'] = 'List-Unsubscribe=One-Click'
      headers['List-Id'] = "<campaign-#{campaign_id}.#{domain}>"
      headers['Feedback-ID'] = "#{campaign_id}:bulk:postal:#{domain.split('.').first}"
      headers['Precedence'] = 'bulk'
    else
      token = SecureRandom.urlsafe_base64(16)
      unsub_https = "https://#{domain}/unsubscribe?eid=#{encoded_email}&token=#{token}"
      unsub_mailto = "mailto:unsubscribe@#{domain}?subject=unsubscribe-#{encoded_email}"

      headers['List-Unsubscribe'] = "<#{unsub_https}>, <#{unsub_mailto}>"
      headers['List-Unsubscribe-Post'] = 'List-Unsubscribe=One-Click'
      headers['Precedence'] = 'bulk'
    end

    headers
  end

  def parse_response(response, to)
    parsed = response.parsed_response

    if response.success?
      data = parsed.is_a?(Hash) ? parsed['data'] : nil
      {
        success: true,
        message_id: data&.dig('messages', to, 'id')&.to_s,
        token: data&.dig('messages', to, 'token')
      }
    else
      error_msg =
        if parsed.is_a?(Hash)
          parsed['error'] || parsed['message']
        elsif parsed.present?
          parsed.to_s
        else
          response.body.to_s.presence || 'Unknown error'
        end

      { success: false, error: error_msg, status: response.code }
    end
  end

  def html_to_text(html)
    return '' if html.blank?

    text = html.dup
    text.gsub!(/\r\n?/, "\n")

    # Block-level elements -> line breaks
    text.gsub!(/<br\s*\/?>/i, "\n")
    text.gsub!(/<\/p>/i, "\n\n")
    text.gsub!(/<\/div>/i, "\n")
    text.gsub!(/<\/h[1-6]>/i, "\n\n")
    text.gsub!(/<\/tr>/i, "\n")
    text.gsub!(/<\/li>/i, "\n")
    text.gsub!(/<li[^>]*>/i, "  - ")

    # Links -> text (URL)
    text.gsub!(/<a\s[^>]*href=["']([^"']*)["'][^>]*>(.*?)<\/a>/im) { "#{Regexp.last_match(2)} (#{Regexp.last_match(1)})" }

    # Strip remaining tags
    text.gsub!(/<[^>]+>/, '')

    # Decode entities
    text.gsub!(/&nbsp;/, ' ')
    text.gsub!(/&amp;/, '&')
    text.gsub!(/&lt;/, '<')
    text.gsub!(/&gt;/, '>')
    text.gsub!(/&quot;/, '"')
    text.gsub!(/&#39;/, "'")
    text.gsub!(/&mdash;/, '—')
    text.gsub!(/&ndash;/, '–')
    text.gsub!(/&#(\d+);/) { ($1.to_i <= 0x10FFFF ? [$1.to_i].pack('U') : $&) rescue $& }

    # Clean up whitespace
    text.gsub!(/[ \t]+/, ' ')
    text.gsub!(/\n{3,}/, "\n\n")
    text.strip
  end
end
