# frozen_string_literal: true

module ApiHelpers
  def auth_headers(api_key)
    { 'Authorization' => "Bearer #{api_key}" }
  end

  def create_api_key_with_raw
    ApiKey.generate(name: 'Test API Key')
  end

  def json_response
    JSON.parse(response.body)
  end
end
