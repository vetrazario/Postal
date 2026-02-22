# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SendToPostalJob, type: :job do
  let(:postal_url) { 'http://postal:5000' }

  before do
    allow(ENV).to receive(:fetch).with('POSTAL_API_URL', 'http://postal:5000').and_return(postal_url)
    allow(ENV).to receive(:fetch).with('POSTAL_API_KEY').and_return('test_api_key')
  end

  describe '#perform' do
    context 'when email_log does not exist' do
      it 'returns without error' do
        expect { SendToPostalJob.perform_now(999_999, '<html></html>') }.not_to raise_error
      end
    end

    context 'when email_log is already sent or delivered' do
      it 'returns without calling Postal when status is sent' do
        email_log = create(:email_log, status: 'sent')

        expect(PostalClient).not_to receive(:new)
        SendToPostalJob.perform_now(email_log.id, '<html></html>')
      end
    end

    context 'when email is blocked (unsubscribed)' do
      it 'updates status to failed and does not call Postal' do
        email_log = create(:email_log, status: 'processing', recipient: 'blocked@example.com', campaign_id: 'camp_1')
        create(:unsubscribe, email: 'blocked@example.com', campaign_id: 'camp_1')

        expect(PostalClient).not_to receive(:new)
        SendToPostalJob.perform_now(email_log.id, '<html></html>')

        email_log.reload
        expect(email_log.status).to eq('failed')
        expect(email_log.status_details).to eq({ 'reason' => 'unsubscribed' })
      end
    end

    context 'when email is blocked (bounced)' do
      it 'updates status to failed and does not call Postal' do
        email_log = create(:email_log, status: 'processing', recipient: 'bounced@example.com', campaign_id: 'camp_2')
        create(:bounced_email, email: 'bounced@example.com', bounce_type: 'hard', campaign_id: 'camp_2')

        expect(PostalClient).not_to receive(:new)
        SendToPostalJob.perform_now(email_log.id, '<html></html>')

        email_log.reload
        expect(email_log.status).to eq('failed')
        expect(email_log.status_details).to eq({ 'reason' => 'bounced' })
      end
    end

    context 'when Postal API returns success' do
      let(:email_log) { create(:email_log, status: 'processing', external_message_id: 'ext_123', recipient: 'user@example.com') }

      before do
        stub_request(:post, "#{postal_url}/api/v1/send/message")
          .to_return(
            status: 200,
            body: { data: { messages: { 'user@example.com' => { id: 'postal_msg_abc', token: 'tok_xyz' } } } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'updates email_log to sent and enqueues ReportToAmsJob' do
        allow(SystemConfig).to receive(:get).with(:domain).and_return('test.example.com')

        expect { SendToPostalJob.perform_now(email_log.id, '<html><body>Hi</body></html>') }
          .to have_enqueued_job(ReportToAmsJob).with('ext_123', 'sent')

        email_log.reload
        expect(email_log.status).to eq('sent')
        expect(email_log.postal_message_id).to eq('postal_msg_abc')
        expect(email_log.sent_at).to be_present
      end
    end

    context 'when Postal API returns error' do
      let(:email_log) { create(:email_log, status: 'processing', external_message_id: 'ext_456') }

      before do
        stub_request(:post, "#{postal_url}/api/v1/send/message")
          .to_return(status: 500, body: { error: 'Internal server error' }.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'updates email_log to failed and enqueues ReportToAmsJob with error' do
        allow(SystemConfig).to receive(:get).with(:domain).and_return('test.example.com')

        expect { SendToPostalJob.perform_now(email_log.id, '<html></html>') }
          .to have_enqueued_job(ReportToAmsJob).with('ext_456', 'failed', 'Internal server error')

        email_log.reload
        expect(email_log.status).to eq('failed')
        expect(email_log.status_details['error']).to eq('Internal server error')
      end
    end
  end
end
