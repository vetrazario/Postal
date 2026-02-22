# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Status API', type: :request do
  let!(:api_key_and_raw) { ApiKey.generate(name: 'Test API Key') }
  let(:api_key) { api_key_and_raw[0] }
  let(:raw_key) { api_key_and_raw[1] }
  let(:headers) { auth_headers(raw_key) }

  before { api_key_and_raw }

  describe 'GET /api/v1/status/:message_id' do
    context 'when message exists' do
      let(:email_log) do
        create(:email_log,
          external_message_id: 'ext_msg_123',
          message_id: 'local_abc123',
          status: 'sent',
          recipient_masked: 'u***@example.com',
          sent_at: 1.hour.ago)
      end

      before { email_log }

      it 'returns 200 with status data' do
        get "/api/v1/status/ext_msg_123", headers: headers

        expect(response).to have_http_status(:ok)
        json = json_response
        expect(json['message_id']).to eq('ext_msg_123')
        expect(json['local_id']).to eq('local_abc123')
        expect(json['status']).to eq('sent')
        expect(json['recipient']).to eq('u***@example.com')
        expect(json['events']).to be_an(Array)
      end
    end

    context 'when message does not exist' do
      it 'returns 404' do
        get "/api/v1/status/nonexistent_msg", headers: headers

        expect(response).to have_http_status(:not_found)
        json = json_response
        expect(json['error']['code']).to eq('not_found')
        expect(json['error']['message']).to eq('Message not found')
      end
    end

    context 'when not authenticated' do
      it 'returns 401' do
        get "/api/v1/status/ext_msg_123"

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
