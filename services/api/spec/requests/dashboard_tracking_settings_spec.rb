# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Dashboard Tracking Settings', type: :request do
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

  describe 'GET /dashboard/tracking_settings' do
    it 'returns 200 and shows tracking settings' do
      get dashboard_tracking_settings_path, headers: basic_auth_header(username, password)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Tracking', 'Open', 'Click')
    end

    it 'returns 401 without auth' do
      get dashboard_tracking_settings_path
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH /dashboard/tracking_settings' do
    it 'updates settings and persists to SystemConfig' do
      config = SystemConfig.instance
      config.update!(enable_open_tracking: false, enable_click_tracking: true)

      patch dashboard_tracking_settings_path,
            params: { tracking_settings: { enable_open_tracking: '1', enable_click_tracking: '0' } },
            headers: basic_auth_header(username, password)

      expect(response).to redirect_to(dashboard_tracking_settings_path)
      follow_redirect!
      expect(response.body).to include('updated successfully')

      config.reload
      expect(config.enable_open_tracking).to eq(true)
      expect(config.enable_click_tracking).to eq(false)
    end

    it 'handles both checkboxes unchecked (empty params)' do
      patch dashboard_tracking_settings_path,
            params: { tracking_settings: {} },
            headers: basic_auth_header(username, password)

      expect(response).to redirect_to(dashboard_tracking_settings_path)
      expect(SystemConfig.instance.enable_open_tracking).to eq(false)
      expect(SystemConfig.instance.enable_click_tracking).to eq(false)
    end
  end

  def basic_auth_header(user, pass)
    credentials = Base64.strict_encode64("#{user}:#{pass}")
    { 'Authorization' => "Basic #{credentials}" }
  end
end
