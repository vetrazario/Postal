class WebhookSender
  def initialize(callback_url:, webhook_secret:, server_id:)
    @callback_url = callback_url
    @webhook_secret = webhook_secret
    @server_id = server_id
  end

  def send(event_type:, data:)
    return unless @callback_url.present?
    
    payload = {
      event_type: event_type,
      timestamp: Time.current.iso8601,
      data: data
    }
    
    timestamp = Time.current.to_i
    signature_data = "#{timestamp}.#{payload.to_json}"
    signature = OpenSSL::HMAC.hexdigest("SHA256", @webhook_secret, signature_data)
    
    response = HTTParty.post(
      @callback_url,
      headers: {
        "Content-Type" => "application/json",
        "X-Signature" => "sha256=#{signature}",
        "X-Timestamp" => timestamp.to_s,
        "X-Server-ID" => @server_id
      },
      body: payload.to_json,
      timeout: 10
    )
    
    {
      success: response.success?,
      status: response.code,
      body: response.parsed_response
    }
  rescue => e
    Rails.logger.error "Webhook error: #{e.message}"
    {
      success: false,
      error: e.message
    }
  end
end





