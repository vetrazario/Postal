# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Email Flow Integration', type: :request do
  let!(:api_key_and_raw) { ApiKey.generate(name: 'Test API Key') }
  let(:raw_key) { api_key_and_raw[1] }
  let(:headers) { auth_headers(raw_key) }

  before do
    api_key_and_raw
    ENV['ALLOWED_SENDER_DOMAINS'] = 'example.com'
    allow(SystemConfig).to receive(:get).with(:domain).and_return('test.example.com')
    allow(ENV).to receive(:fetch).and_call_original
  end

  after { ENV.delete('ALLOWED_SENDER_DOMAINS') }

  it 'POST /send creates EmailLog, BuildEmailJob enqueues SendToPostalJob, and SendToPostalJob updates status' do
    postal_url = 'http://postal:5000'
    allow(ENV).to receive(:fetch).with('POSTAL_API_URL', 'http://postal:5000').and_return(postal_url)
    allow(ENV).to receive(:fetch).with('POSTAL_API_KEY').and_return('test_key')

    stub_request(:post, "#{postal_url}/api/v1/send/message")
      .to_return(
        status: 200,
        body: { data: { messages: { 'user@example.com' => { id: 'postal_123', token: 'tok' } } } }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    # Step 1: Send email via API
    post '/api/v1/send',
      params: {
        recipient: 'user@example.com',
        from_email: 'sender@example.com',
        from_name: 'Sender',
        subject: 'Test',
        variables: { body: '<p>Hello</p>' },
        tracking: { campaign_id: 'camp_1', message_id: 'ext_1' }
      },
      headers: headers,
      as: :json

    expect(response).to have_http_status(:accepted)
    json = JSON.parse(response.body)
    message_id = json['message_id']
    external_id = json['external_message_id'] || 'ext_1'

    # Step 2: Find EmailLog and run BuildEmailJob
    email_log = EmailLog.find_by(message_id: message_id) || EmailLog.find_by(external_message_id: external_id)
    expect(email_log).to be_present
    expect(email_log.status).to eq('queued')

    # Step 3: Perform BuildEmailJob and SendToPostalJob (both enqueued)
    perform_enqueued_jobs
    perform_enqueued_jobs # Second call for SendToPostalJob enqueued by BuildEmailJob
    email_log.reload

    # Step 4: Verify SendToPostalJob was performed and status updated
    expect(email_log.status).to eq('sent')
    expect(email_log.postal_message_id).to eq('postal_123')
  end
end
