# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Tracking Open', type: :request do
  # Tracking endpoints don't require API auth
  describe 'GET /t/o/:token' do
    context 'with valid token' do
      let(:token) { SecureRandom.urlsafe_base64(32) }
      let(:email_log) { create(:email_log) }
      let(:email_open) { create(:email_open, email_log: email_log, token: token) }

      before { email_open }

      it 'returns 200 with image/gif' do
        get "/t/o/#{token}"

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq('image/gif')
        expect(response.body).to be_present
      end
    end

    context 'with invalid token' do
      it 'returns 200 with pixel anyway (graceful degradation)' do
        get '/t/o/invalid_token_xyz'

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq('image/gif')
      end
    end

    context 'with token having .gif extension' do
      let(:token) { SecureRandom.urlsafe_base64(32) }
      let(:email_log) { create(:email_log) }
      let(:email_open) { create(:email_open, email_log: email_log, token: token) }

      before { email_open }

      it 'finds token without .gif suffix' do
        get "/t/o/#{token}.gif"

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq('image/gif')
      end
    end
  end
end
