require 'rails_helper'

RSpec.describe "Health", type: :request do
  describe "GET /api/v1/health" do
    it "returns healthy status" do
      get "/api/v1/health"
      
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("healthy")
      expect(json["timestamp"]).to be_present
      expect(json["checks"]).to be_present
    end
  end
end





