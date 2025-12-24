require 'rails_helper'

RSpec.describe "Batches", type: :request do
  # Use ApiKey.generate to ensure key_hash is correctly set
  let!(:api_key_and_raw) { ApiKey.generate(name: "Test API Key") }
  let!(:api_key) { api_key_and_raw[0] }
  let(:raw_key) { api_key_and_raw[1] }
  let(:headers) { auth_headers(raw_key) }

  before do
    ENV['ALLOWED_SENDER_DOMAINS'] = 'example.com'
  end

  after do
    ENV.delete('ALLOWED_SENDER_DOMAINS')
  end

  describe "POST /api/v1/batch" do
    let(:valid_params) do
      {
        from_name: "Test Sender",
        from_email: "sender@example.com",
        subject: "Test Subject",
        html_body: "<html><body><h1>Test</h1></body></html>",
        campaign_id: "camp_123",
        messages: [
          {
            recipient: "user1@example.com",
            message_id: "msg_1",
            html_body: "<html><body><h1>User 1</h1></body></html>"
          },
          {
            recipient: "user2@example.com",
            message_id: "msg_2",
            html_body: "<html><body><h1>User 2</h1></body></html>"
          }
        ]
      }
    end

    it "processes batch and returns 202" do
      post "/api/v1/batch", params: valid_params, headers: headers, as: :json
      
      expect(response).to have_http_status(:accepted)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("queued")
      expect(json["batch_id"]).to be_present
      expect(json["queued"]).to eq(2)
    end

    it "requires authentication" do
      post "/api/v1/batch", params: valid_params, as: :json
      
      expect(response).to have_http_status(:unauthorized)
    end

    it "validates batch size" do
      large_batch = valid_params.merge(messages: Array.new(101) { { recipient: "user@example.com" } })
      post "/api/v1/batch", params: large_batch, headers: headers, as: :json
      
      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json["error"]["code"]).to eq("validation_error")
    end

    it "handles partial failures" do
      mixed_params = valid_params.merge(
        messages: [
          { recipient: "valid@example.com", message_id: "msg_1" },
          { recipient: "invalid-email", message_id: "msg_2" }
        ]
      )
      
      post "/api/v1/batch", params: mixed_params, headers: headers, as: :json
      
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("partial")
      expect(json["queued"]).to eq(1)
      expect(json["failed"]).to eq(1)
    end
  end
end

