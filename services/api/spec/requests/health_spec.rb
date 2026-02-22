require 'rails_helper'

RSpec.describe "Health", type: :request do
  before do
    postal_url = ENV.fetch('POSTAL_API_URL', 'http://postal:5000')
    stub_request(:get, "#{postal_url}/api/v1/health").to_return(status: 200)
  end

  describe "GET /api/v1/health" do
    it "returns healthy status" do
      get "/api/v1/health"
      
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["status"]).to be_in(%w[healthy degraded])
      expect(json["timestamp"]).to be_present
      expect(json["checks"]).to be_present
    end
  end
end





