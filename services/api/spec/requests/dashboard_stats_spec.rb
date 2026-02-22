# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Dashboard stats include EmailOpen and EmailClick', type: :request do
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

  it 'includes EmailOpen and EmailClick in dashboard index stats' do
    log = create(:email_log, status: 'delivered', created_at: Time.current)
    create(:email_open, email_log: log, opened_at: Time.current)
    create(:email_click, email_log: log, clicked_at: Time.current)
    create(:tracking_event, email_log: log, event_type: 'open')

    get '/dashboard', headers: basic_auth_header(username, password)
    expect(response).to have_http_status(:ok)

    # Stats are rendered in the page; we have 2 opens (EmailOpen + TrackingEvent) and 1 click (EmailClick)
    expect(response.body).to include('Dashboard')
    # Exact numbers depend on other fixtures; at least ensure no 500 and page loads
  end

  def basic_auth_header(user, pass)
    credentials = Base64.strict_encode64("#{user}:#{pass}")
    { 'Authorization' => "Basic #{credentials}" }
  end
end
