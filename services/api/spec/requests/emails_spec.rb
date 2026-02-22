require 'rails_helper'

RSpec.describe "Emails", type: :request do
  before do
    ENV['ALLOWED_SENDER_DOMAINS'] = 'example.com'
  end

  after { ENV.delete('ALLOWED_SENDER_DOMAINS') }

  # Use ApiKey.generate to ensure key_hash is correctly set
  let(:api_key_and_raw) { ApiKey.generate(name: "Test API Key") }
  let(:api_key) { api_key_and_raw[0] }
  let(:raw_key) { api_key_and_raw[1] }
  let(:headers) { auth_headers(raw_key) }
  
  before do
    # Ensure key is created and persisted before tests
    api_key_and_raw
    api_key.reload
    # Verify key exists in database
    expect(ApiKey.find_by(key_hash: Digest::SHA256.hexdigest(raw_key))).to be_present
  end

  describe "POST /api/v1/send" do
    let(:valid_params) do
      {
        recipient: "user@example.com",
        html_body: "<html><body><h1>Hello John</h1></body></html>",
        from_name: "Test Sender",
        from_email: "test@example.com",
        subject: "Test Subject",
        tracking: {
          campaign_id: "camp_123",
          message_id: "msg_456"
        }
      }
    end

    it "creates email log and returns 202" do
      # Debug: verify key works
      auth_result = ApiKeyAuthenticator.call(raw_key)
      expect(auth_result).to eq(api_key), "Auth failed: expected #{api_key.id}, got #{auth_result&.id}"
      
      # Debug: verify headers
      expect(headers["Authorization"]).to be_present
      expect(headers["Authorization"]).to start_with("Bearer ")
      
      post "/api/v1/send", params: valid_params, headers: headers, as: :json
      
      # Debug: check response if failed
      if response.status != 202
        $stderr.puts "Response status: #{response.status}"
        $stderr.puts "Response body: #{response.body}"
        $stderr.puts "Headers sent: #{headers.inspect}"
      end
      
      expect(response).to have_http_status(:accepted)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("queued")
      expect(json["message_id"]).to be_present
        expect(json["message_id"]).to match(/^[a-z0-9]+\.[a-zA-Z0-9]{24}(?:@.+)?$/)
    end

    it "requires authentication" do
      post "/api/v1/send", params: valid_params, as: :json
      
      expect(response).to have_http_status(:unauthorized)
    end

    it "validates recipient email" do
      post "/api/v1/send", params: valid_params.merge(recipient: "invalid"), headers: headers, as: :json
      
      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json["error"]["code"]).to eq("validation_error")
    end
  end
end





