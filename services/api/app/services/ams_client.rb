# frozen_string_literal: true

class AmsClient
  class AmsError < StandardError; end
  class ConnectionError < AmsError; end
  class AuthenticationError < AmsError; end
  class ApiError < AmsError; end

  def initialize(api_url:, api_key:)
    @api_url = api_url.to_s.strip
    @api_key = api_key.to_s.strip
    
    raise ArgumentError, 'AMS API URL is required' if @api_url.blank?
    raise ArgumentError, 'AMS API Key is required' if @api_key.blank?
  end

  def get_mailings
    call_api('getMailings')
  end

  def get_mailing(id)
    call_api('getMailing', { id: id })
  end

  def stop_mailing(id)
    call_api('stopMailing', { id: id })
  end

  def start_mailing(id)
    call_api('startMailing', { id: id })
  end

  def get_sending_job_result(job_id:, mailing_id:)
    call_api('getSendingJobResult', { jobID: job_id, mailingID: mailing_id })
  end

  def send_threshold_alert(campaign_id:, violations:)
    # Отправка уведомления о превышении порогов в AMS
    # Если AMS API поддерживает такой метод, можно использовать его
    # Пока что просто логируем
    Rails.logger.info "Threshold alert for campaign #{campaign_id}: #{violations.map { |v| v[:message] }.join('; ')}"
    
    # Если AMS API имеет метод для уведомлений, можно добавить:
    # call_api('sendThresholdAlert', { campaign_id: campaign_id, violations: violations })
    
    { success: true }
  end

  def test_connection
    result = get_mailings
    if result[:success]
      { success: true, message: 'Connection successful' }
    else
      { success: false, error: result[:error] }
    end
  rescue StandardError => e
    { success: false, error: e.message }
  end

  private

  def call_api(method, params = {})
    request_id = SecureRandom.uuid
    
    body = {
      jsonrpc: '2.0',
      method: method,
      params: params.merge(apiKey: @api_key),
      id: request_id
    }

    response = HTTParty.post(
      @api_url,
      headers: {
        'Content-Type' => 'application/json'
      },
      body: body.to_json,
      timeout: 30
    )

    parsed = response.parsed_response

    if parsed.is_a?(Hash) && parsed['error']
      error_msg = parsed['error']['message'] || parsed['error'].to_s
      error_code = parsed['error']['code']
      
      case error_code
      when -32602, -32603
        raise AuthenticationError, error_msg
      else
        raise ApiError, error_msg
      end
    end

    if response.success?
      { success: true, result: parsed['result'] }
    else
      { success: false, error: "HTTP #{response.code}: #{response.body}" }
    end
  rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout => e
    raise ConnectionError, "Connection failed: #{e.message}"
  rescue JSON::ParserError => e
    raise ApiError, "Invalid JSON response: #{e.message}"
  end
end

