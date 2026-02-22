require 'rails_helper'

RSpec.describe "Rate Limiting", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  before do
    Rack::Attack.enabled = true
    Rack::Attack.cache.store.clear
  end

  describe "POST /api/v1/send" do
    let(:api_key_and_raw) { ApiKey.generate(name: "Test API Key") }
    let(:api_key) { api_key_and_raw[0] }
    let(:raw_key) { api_key_and_raw[1] }
    let(:headers) { auth_headers(raw_key) }
    let(:valid_params) do
      {
        recipient: "user@example.com",
        html_body: "<html><body><h1>Test</h1></body></html>",
        from_name: "Test Sender",
        from_email: "test@example.com",
        subject: "Test Subject"
      }
    end

    before do
      api_key_and_raw
      api_key.reload
      ENV['ALLOWED_SENDER_DOMAINS'] = 'example.com'
    end

    after { ENV.delete('ALLOWED_SENDER_DOMAINS') }

    it "allows requests within limit (100 req/min)" do
      # Делаем 50 запросов - должно пройти
      50.times do
        post "/api/v1/send", params: valid_params, headers: headers, as: :json
        expect(response).to have_http_status(:accepted)
      end
    end

    it "throttles after 100 requests per minute" do
      # Делаем 100 запросов - все должны пройти
      100.times do
        post "/api/v1/send", params: valid_params, headers: headers, as: :json
        expect(response).to have_http_status(:accepted)
      end

      # 101-й запрос должен быть заблокирован
      post "/api/v1/send", params: valid_params, headers: headers, as: :json
      expect(response).to have_http_status(:too_many_requests)
      
      json = JSON.parse(response.body)
      expect(json["error"]["code"]).to eq("rate_limit_exceeded")
      expect(response.headers["Retry-After"]).to be_present
    end

    it "resets limit after 1 minute" do
      # Делаем 100 запросов
      100.times do
        post "/api/v1/send", params: valid_params, headers: headers, as: :json
      end

      # Проверяем, что 101-й заблокирован
      post "/api/v1/send", params: valid_params, headers: headers, as: :json
      expect(response).to have_http_status(:too_many_requests)

      # Перемещаем время вперед на 1 минуту
      travel 1.minute do
        # Теперь запрос должен пройти
        post "/api/v1/send", params: valid_params, headers: headers, as: :json
        expect(response).to have_http_status(:accepted)
      end
    end
  end

  describe "POST /api/v1/batch" do
    let(:api_key_and_raw) { ApiKey.generate(name: "Test API Key") }
    let(:api_key) { api_key_and_raw[0] }
    let(:raw_key) { api_key_and_raw[1] }
    let(:headers) { auth_headers(raw_key) }
    let(:valid_params) do
      {
        emails: [
          {
            recipient: "user1@example.com",
            html_body: "<html><body><h1>Test</h1></body></html>",
            from_name: "Test Sender",
            from_email: "test@example.com",
            subject: "Test Subject"
          }
        ]
      }
    end

    before do
      api_key_and_raw
      api_key.reload
      ENV['ALLOWED_SENDER_DOMAINS'] = 'example.com'
    end

    after { ENV.delete('ALLOWED_SENDER_DOMAINS') }

    it "throttles batch endpoint after 100 requests per minute" do
      # Делаем 100 запросов
      100.times do
        post "/api/v1/batch", params: valid_params, headers: headers, as: :json
        expect(response).to have_http_status(:accepted)
      end

      # 101-й запрос должен быть заблокирован
      post "/api/v1/batch", params: valid_params, headers: headers, as: :json
      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe "GET /api/v1/health" do
    it "is not throttled (safelist)" do
      # Делаем много запросов к health check - все должны пройти
      200.times do
        get "/api/v1/health"
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "Failed authentication attempts" do
    it "throttles failed auth attempts (10/min per IP)" do
      invalid_key = "invalid_key_12345"
      headers = { "Authorization" => "Bearer #{invalid_key}" }

      # Делаем 10 неуспешных попыток - все должны вернуть 401
      10.times do
        post "/api/v1/send", 
          params: { recipient: "test@example.com", html_body: "test" },
          headers: headers,
          as: :json
        expect(response).to have_http_status(:unauthorized)
      end

      # 11-я попытка должна быть заблокирована
      post "/api/v1/send", 
        params: { recipient: "test@example.com", html_body: "test" },
        headers: headers,
        as: :json
      expect(response).to have_http_status(:too_many_requests)
    end
  end

  private

  def auth_headers(raw_key)
    { "Authorization" => "Bearer #{raw_key}" }
  end
end


