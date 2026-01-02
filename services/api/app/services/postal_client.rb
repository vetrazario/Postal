class PostalClient
  def initialize(api_url:, api_key:)
    @api_url = api_url
    @api_key = api_key
  end

  def send_message(to:, from:, subject:, html_body:, headers: {}, tag: nil)
    domain = SystemConfig.get(:domain) || 'localhost'
    message_headers = build_headers(from, to, subject, domain).merge(headers)

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
        bounce: true
      }.to_json,
      timeout: 30
    }

    # Only enable debug output in development (but filter sensitive headers)
    if Rails.env.development? && ENV['DEBUG_HTTP'] == 'true'
      request_options[:debug_output] = FilteredLogger.new(Rails.logger)
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

  def build_headers(from, to, subject, domain)
    {
      'From' => from,
      'To' => to,
      'Subject' => subject,
      'Message-ID' => MessageIdGenerator.generate,
      'Date' => Time.current.rfc2822,
      'Return-Path' => "bounce@#{domain}",
      'Reply-To' => "reply@#{domain}",
      'List-Unsubscribe' => "<mailto:unsubscribe@#{domain}>"
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
