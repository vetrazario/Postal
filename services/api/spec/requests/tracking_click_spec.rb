# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Tracking Click', type: :request do
  describe 'GET /t/c/:token' do
    context 'with valid token and safe URL' do
      let(:token) { SecureRandom.urlsafe_base64(32) }
      let(:email_log) { create(:email_log) }
      let(:email_click) do
        create(:email_click,
          email_log: email_log,
          token: token,
          url: 'https://example.com/safe-page')
      end

      before { email_click }

      it 'redirects to the target URL' do
        get "/t/c/#{token}", headers: { 'HTTP_HOST' => 'test.host' }

        expect(response).to have_http_status(:moved_permanently)
        expect(response).to redirect_to('https://example.com/safe-page')
      end
    end

    context 'with invalid token' do
      it 'redirects to root' do
        get '/t/c/invalid_token_xyz', headers: { 'HTTP_HOST' => 'test.host' }

        expect(response).to have_http_status(:moved_permanently)
        expect(response).to redirect_to('http://test.host/')
      end
    end

    context 'with unsafe URL (javascript:)' do
      let(:token) { SecureRandom.urlsafe_base64(32) }
      let(:email_log) { create(:email_log) }
      let(:email_click) do
        create(:email_click,
          email_log: email_log,
          token: token,
          url: 'javascript:alert(1)')
      end

      before { email_click }

      it 'redirects to root instead of javascript URL' do
        get "/t/c/#{token}", headers: { 'HTTP_HOST' => 'test.host' }

        expect(response).to have_http_status(:moved_permanently)
        expect(response).to redirect_to('http://test.host/')
      end
    end
  end
end
