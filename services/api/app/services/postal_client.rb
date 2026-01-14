class PostalClient
  def initialize(api_url:, api_key:)
    @api_url = api_url
    @api_key = api_key
  end

  def send_message(to:, from:, subject:, html_body:, headers: {}, tag: nil, campaign_id: nil, track_clicks: true, track_opens: true)
    domain = SystemConfig.get(:domain) || 'localhost'
    message_headers = build_headers(from, to, subject, domain, campaign_id).merge(headers)

    # Log the request details for debugging
    Rails.logger.info "PostalClient: Sending to #{@api_url}/api/v1/send/message with Host: #{domain}"

    response = HTTParty.post(
      "#{@api_url}/api/v1/send/message",
      headers: {
        'Host' => domain,
        'X-Server-API-Key' => @api_key,
        'Content-Type' => 'application/json'
      },
      debug_output: Rails.logger,
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
      }.to_json
    )

    parse_response(response, to)
  rescue StandardError => e
    { success: false, error: e.message }
  end

  private

  def build_headers(from, to, subject, domain, campaign_id = nil)
    # Build unsubscribe URL with encoded parameters
    encoded_email = Base64.urlsafe_encode64(to)
    encoded_cid = campaign_id ? Base64.urlsafe_encode64(campaign_id) : ''
    unsubscribe_url = "https://#{domain}/unsubscribe?eid=#{encoded_email}&cid=#{encoded_cid}"

    {
      'From' => from,
      'To' => to,
      'Subject' => subject,
      'Message-ID' => MessageIdGenerator.generate,
      'Date' => Time.current.rfc2822,
      'Return-Path' => "bounce@#{domain}",
      'Reply-To' => "reply@#{domain}",
      'List-Unsubscribe' => "<#{unsubscribe_url}>, <mailto:unsubscribe@#{domain}>",
      'List-Unsubscribe-Post' => 'List-Unsubscribe=One-Click'
    }
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
    html.gsub(/<[^>]+>/, '')
        .gsub(/&nbsp;/, ' ')
        .gsub(/&amp;/, '&')
        .gsub(/&lt;/, '<')
        .gsub(/&gt;/, '>')
        .gsub(/&quot;/, '"')
        .strip
  end
end
