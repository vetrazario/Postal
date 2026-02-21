# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Dashboard flash[:warning] display', type: :request do
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

  it 'displays flash[:warning] in yellow block when set' do
    config = SystemConfig.instance
    allow(SystemConfig).to receive(:instance).and_return(config)
    allow(config).to receive(:update).and_return(true)
    allow(config).to receive(:sync_to_env_file).and_return(nil)
    allow(config).to receive(:restart_required?).and_return(true)
    allow(config).to receive(:restart_services).and_return(['api'])

    patch update_system_config_dashboard_settings_path,
          params: { system_config: { domain: config.domain } },
          headers: basic_auth_header(username, password)

    expect(response).to redirect_to(dashboard_settings_path)
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('yellow-50').or include('text-yellow-800')
    expect(response.body).to include('Restart').or include('restart')
  end

  def basic_auth_header(user, pass)
    credentials = Base64.strict_encode64("#{user}:#{pass}")
    { 'Authorization' => "Basic #{credentials}" }
  end
end
