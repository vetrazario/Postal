require 'rails_helper'

RSpec.describe "Dashboard", type: :request do
  let(:username) { 'test_admin' }
  let(:password) { 'test_password_123' }
  
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:[]).with('DASHBOARD_USERNAME').and_return(username)
    allow(ENV).to receive(:fetch).with('DASHBOARD_USERNAME', anything).and_return(username)
    allow(ENV).to receive(:[]).with('DASHBOARD_PASSWORD').and_return(password)
    allow(ENV).to receive(:fetch).with('DASHBOARD_PASSWORD', anything).and_return(password)
  end

  describe "GET /dashboard" do
    context "without authentication" do
      it "returns 401 Unauthorized" do
        get "/dashboard"
        
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with invalid credentials" do
      it "returns 401 Unauthorized with wrong username" do
        get "/dashboard", headers: basic_auth_header('wrong_user', password)
        
        expect(response).to have_http_status(:unauthorized)
      end

      it "returns 401 Unauthorized with wrong password" do
        get "/dashboard", headers: basic_auth_header(username, 'wrong_password')
        
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with valid authentication" do
      it "returns 200 OK" do
        get "/dashboard", headers: basic_auth_header(username, password)
        
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Dashboard")
      end
    end
  end

  describe "GET /dashboard/logs" do
    context "without authentication" do
      it "returns 401 Unauthorized" do
        get "/dashboard/logs"
        
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with valid authentication" do
      it "returns 200 OK" do
        get "/dashboard/logs", headers: basic_auth_header(username, password)
        
        expect(response).to have_http_status(:ok)
      end
    end
  end

  private

  def basic_auth_header(username, password)
    credentials = Base64.strict_encode64("#{username}:#{password}")
    { "Authorization" => "Basic #{credentials}" }
  end
end

