class PostalClient
  def initialize(api_url:, api_key:)
    @api_url = api_url
    @api_key = api_key
  end

  def send_message(to:, from:, subject:, html_body:, headers: {}, tag: nil)
    domain = ENV.fetch('DOMAIN', 'send1.example.com')

    message_headers = build_headers(from, to, subject, domain).merge(headers)

    response = HTTParty.post(
      "#{@api_url}/api/v1/send/message",
      headers: { 'X-Server-API-Key' => @api_key, 'Content-Type' => 'application/json' },
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
      }.to_json
    )

    parse_response(response, to)
  rescue StandardError => e
    { success: false, error: e.message }
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
    if response.success?
      data = response.parsed_response['data']
      {
        success: true,
        message_id: data&.dig('messages', to, 'id')&.to_s,
        token: data&.dig('messages', to, 'token')
      }
    else
      { success: false, error: response.parsed_response['error'] || 'Unknown error', status: response.code }
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
