# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BuildEmailJob, type: :job do
  before do
    allow(SystemConfig).to receive(:get).with(:domain).and_return('test.example.com')
  end

  describe '#perform' do
    context 'when email_log does not exist' do
      it 'returns without error' do
        expect { BuildEmailJob.perform_now(999_999) }.not_to raise_error
      end

      it 'does not enqueue SendToPostalJob' do
        expect { BuildEmailJob.perform_now(999_999) }.not_to have_enqueued_job(SendToPostalJob)
      end
    end

    context 'when email_log is already sent or delivered' do
      it 'returns without enqueueing when status is sent' do
        email_log = create(:email_log, status: 'sent')

        expect { BuildEmailJob.perform_now(email_log.id) }.not_to have_enqueued_job(SendToPostalJob)
      end

      it 'returns without enqueueing when status is delivered' do
        email_log = create(:email_log, status: 'delivered')

        expect { BuildEmailJob.perform_now(email_log.id) }.not_to have_enqueued_job(SendToPostalJob)
      end
    end

    context 'when email is blocked (unsubscribed)' do
      it 'updates status to failed and does not enqueue SendToPostalJob' do
        email_log = create(:email_log, status: 'queued', recipient: 'blocked@example.com', campaign_id: 'camp_1')
        create(:unsubscribe, email: 'blocked@example.com', campaign_id: 'camp_1')

        expect { BuildEmailJob.perform_now(email_log.id) }.not_to have_enqueued_job(SendToPostalJob)

        email_log.reload
        expect(email_log.status).to eq('failed')
        expect(email_log.status_details).to eq({ 'reason' => 'unsubscribed' })
      end
    end

    context 'when email is blocked (bounced)' do
      it 'updates status to failed and does not enqueue SendToPostalJob' do
        email_log = create(:email_log, status: 'queued', recipient: 'bounced@example.com', campaign_id: 'camp_2')
        create(:bounced_email, email: 'bounced@example.com', bounce_type: 'hard', campaign_id: 'camp_2')

        expect { BuildEmailJob.perform_now(email_log.id) }.not_to have_enqueued_job(SendToPostalJob)

        email_log.reload
        expect(email_log.status).to eq('failed')
        expect(email_log.status_details).to eq({ 'reason' => 'bounced' })
      end
    end

    context 'when email is not blocked' do
      it 'enqueues SendToPostalJob with html_body containing tracking' do
        email_log = create(:email_log, status: 'queued', status_details: { 'variables' => { 'body' => 'Hello' } })

        expect { BuildEmailJob.perform_now(email_log.id) }.to have_enqueued_job(SendToPostalJob)
          .with(email_log.id, a_string_including('/track/o'))

        email_log.reload
        expect(email_log.status).to eq('processing')
      end
    end
  end
end
