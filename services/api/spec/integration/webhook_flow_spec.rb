# frozen_string_literal: true

require 'rails_helper'
require_relative '../../app/lib/encrypto_signo'

RSpec.describe 'Webhook Flow Integration', type: :request do
  let(:private_key) { OpenSSL::PKey::RSA.new(2048) }
  let(:public_key_pem) { private_key.public_key.to_pem }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:[]).with('POSTAL_WEBHOOK_PUBLIC_KEY').and_return(public_key_pem)
    allow(ENV).to receive(:fetch).with('POSTAL_WEBHOOK_PUBLIC_KEY', anything).and_return(public_key_pem)
  end

  it 'POST /webhook with MessageDelivered updates EmailLog status to delivered' do
    email_log = create(:email_log, postal_message_id: 'postal_999', status: 'sent')

    raw_body = {
      event: 'MessageDelivered',
      payload: {
        message: { id: 'postal_999', token: 'tok' }
      }
    }.to_json

    signature = EncryptoSigno.sign(private_key, raw_body)

    post '/api/v1/webhook',
      params: {},
      headers: {
        'Content-Type' => 'application/json',
        'X-Postal-Signature-256' => signature
      },
      env: { 'RAW_POST_DATA' => raw_body }

    expect(response).to have_http_status(:ok)

    email_log.reload
    expect(email_log.status).to eq('delivered')
  end
end
