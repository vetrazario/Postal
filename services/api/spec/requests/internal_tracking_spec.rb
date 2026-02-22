# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Internal Tracking API', type: :request do
  # Internal tracking uses WEBHOOK_SECRET (HMAC) or trusted_source (localhost)
  # In test, request comes from localhost so trusted_source should allow it
  before do
    allow(ENV).to receive(:[]).with('WEBHOOK_SECRET').and_return(nil)
  end

  describe 'POST /api/v1/internal/tracking_event' do
    context 'when message exists' do
      let(:email_log) { create(:email_log, external_message_id: 'ext_track_123', message_id: 'local_xyz') }

      before { email_log }

      it 'returns 200 for opened event' do
        post '/api/v1/internal/tracking_event',
          params: { message_id: 'ext_track_123', event_type: 'opened', data: {} },
          headers: { 'REMOTE_ADDR' => '127.0.0.1' }

        expect(response).to have_http_status(:ok)
        json = json_response
        expect(json['success']).to be true
      end

      it 'returns 200 for clicked event' do
        post '/api/v1/internal/tracking_event',
          params: { message_id: 'ext_track_123', event_type: 'clicked', data: { url: 'https://example.com' } },
          headers: { 'REMOTE_ADDR' => '127.0.0.1' }

        expect(response).to have_http_status(:ok)
      end
    end

    context 'when message does not exist' do
      it 'returns 404' do
        post '/api/v1/internal/tracking_event',
          params: { message_id: 'nonexistent', event_type: 'opened', data: {} },
          headers: { 'REMOTE_ADDR' => '127.0.0.1' }

        expect(response).to have_http_status(:not_found)
        json = json_response
        expect(json['error']).to eq('Message not found')
      end
    end

    context 'when request is not from trusted source and no WEBHOOK_SECRET' do
      it 'returns 401 for external IP' do
        post '/api/v1/internal/tracking_event',
          params: { message_id: 'ext_123', event_type: 'opened', data: {} },
          headers: { 'REMOTE_ADDR' => '8.8.8.8' }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
