# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EmailBlocker do
  describe '.blocked?' do
    context 'when email is unsubscribed' do
      it 'returns blocked with reason unsubscribed for global unsubscribe' do
        create(:unsubscribe, email: 'blocked@example.com', campaign_id: nil)

        result = EmailBlocker.blocked?(email: 'blocked@example.com', campaign_id: nil)

        expect(result).to eq(blocked: true, reason: 'unsubscribed')
      end

      it 'returns blocked with reason unsubscribed for campaign-specific unsubscribe' do
        create(:unsubscribe, email: 'blocked@example.com', campaign_id: 'camp_123')

        result = EmailBlocker.blocked?(email: 'blocked@example.com', campaign_id: 'camp_123')

        expect(result).to eq(blocked: true, reason: 'unsubscribed')
      end
    end

    context 'when email is bounced' do
      it 'returns blocked with reason bounced for global bounce' do
        create(:bounced_email, email: 'bounced@example.com', bounce_type: 'hard', campaign_id: nil)

        result = EmailBlocker.blocked?(email: 'bounced@example.com', campaign_id: nil)

        expect(result).to eq(blocked: true, reason: 'bounced')
      end

      it 'returns blocked with reason bounced for campaign-specific bounce' do
        create(:bounced_email, email: 'bounced@example.com', bounce_type: 'hard', campaign_id: 'camp_456')

        result = EmailBlocker.blocked?(email: 'bounced@example.com', campaign_id: 'camp_456')

        expect(result).to eq(blocked: true, reason: 'bounced')
      end
    end

    context 'when email is not blocked' do
      it 'returns not blocked' do
        result = EmailBlocker.blocked?(email: 'ok@example.com', campaign_id: nil)

        expect(result).to eq(blocked: false)
      end

      it 'returns not blocked when campaign has no unsubscribe or bounce' do
        create(:unsubscribe, email: 'other@example.com', campaign_id: 'other_camp')

        result = EmailBlocker.blocked?(email: 'ok@example.com', campaign_id: 'camp_789')

        expect(result).to eq(blocked: false)
      end
    end

    context 'when unsubscribe takes precedence over bounce' do
      it 'returns unsubscribed when both exist' do
        create(:unsubscribe, email: 'both@example.com', campaign_id: nil)
        create(:bounced_email, email: 'both@example.com', bounce_type: 'hard', campaign_id: nil)

        result = EmailBlocker.blocked?(email: 'both@example.com', campaign_id: nil)

        expect(result).to eq(blocked: true, reason: 'unsubscribed')
      end
    end
  end
end
