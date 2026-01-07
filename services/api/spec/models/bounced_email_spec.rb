# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BouncedEmail, type: :model do
  describe 'validations' do
    it 'requires email' do
      bounce = BouncedEmail.new(bounce_type: 'hard', first_bounced_at: Time.current, last_bounced_at: Time.current)
      expect(bounce).not_to be_valid
      expect(bounce.errors[:email]).to be_present
    end

    it 'requires bounce_type' do
      bounce = BouncedEmail.new(email: 'test@example.com', first_bounced_at: Time.current, last_bounced_at: Time.current)
      expect(bounce).not_to be_valid
      expect(bounce.errors[:bounce_type]).to be_present
    end

    it 'validates bounce_type inclusion' do
      bounce = BouncedEmail.new(
        email: 'test@example.com',
        bounce_type: 'invalid',
        first_bounced_at: Time.current,
        last_bounced_at: Time.current
      )
      expect(bounce).not_to be_valid
      expect(bounce.errors[:bounce_type]).to be_present
    end

    it 'validates bounce_category inclusion' do
      bounce = BouncedEmail.new(
        email: 'test@example.com',
        bounce_type: 'hard',
        bounce_category: 'invalid_category',
        first_bounced_at: Time.current,
        last_bounced_at: Time.current
      )
      expect(bounce).not_to be_valid
      expect(bounce.errors[:bounce_category]).to be_present
    end
  end

  describe '.blocked?' do
    it 'returns true for hard bounce' do
      create(:bounced_email, email: 'test@example.com', bounce_type: 'hard', campaign_id: nil)
      expect(BouncedEmail.blocked?(email: 'test@example.com', campaign_id: nil)).to be true
    end

    it 'returns false for non-bounced email' do
      expect(BouncedEmail.blocked?(email: 'nonexistent@example.com', campaign_id: nil)).to be false
    end

    it 'returns true for campaign-specific bounce' do
      create(:bounced_email, email: 'test@example.com', bounce_type: 'hard', campaign_id: 'campaign_123')
      expect(BouncedEmail.blocked?(email: 'test@example.com', campaign_id: 'campaign_123')).to be true
    end
  end

  describe '.record_bounce_if_needed' do
    it 'does not record for rate_limit' do
      count_before = BouncedEmail.where(email: 'test@example.com').count
      
      BouncedEmail.record_bounce_if_needed(
        email: 'test@example.com',
        bounce_category: :rate_limit,
        smtp_code: '421'
      )
      
      count_after = BouncedEmail.where(email: 'test@example.com').count
      expect(count_after).to eq(count_before)
    end

    it 'records for user_not_found' do
      BouncedEmail.record_bounce_if_needed(
        email: 'test@example.com',
        bounce_category: :user_not_found,
        smtp_code: '550 5.1.1'
      )
      
      bounce = BouncedEmail.find_by(email: 'test@example.com')
      expect(bounce).not_to be_nil
      expect(bounce.bounce_type).to eq('hard')
      expect(bounce.bounce_category).to eq('user_not_found')
    end

    it 'does not record for temporary' do
      count_before = BouncedEmail.where(email: 'test@example.com').count
      
      BouncedEmail.record_bounce_if_needed(
        email: 'test@example.com',
        bounce_category: :temporary,
        smtp_code: '421'
      )
      
      count_after = BouncedEmail.where(email: 'test@example.com').count
      expect(count_after).to eq(count_before)
    end
  end

  describe '#status_description' do
    it 'returns correct description for user_not_found' do
      bounce = BouncedEmail.new(bounce_category: 'user_not_found')
      expect(bounce.status_description).to eq('Hard: Not Found')
    end

    it 'returns correct description for mailbox_full' do
      bounce = BouncedEmail.new(bounce_category: 'mailbox_full')
      expect(bounce.status_description).to eq('Hard: Mailbox Full')
    end

    it 'returns correct description for rate_limit' do
      bounce = BouncedEmail.new(bounce_category: 'rate_limit')
      expect(bounce.status_description).to eq('Rate Limited')
    end

    it 'returns correct description for unknown category' do
      bounce = BouncedEmail.new(bounce_category: 'unknown')
      expect(bounce.status_description).to eq('Hard: Unknown')
    end
  end

  describe 'scopes' do
    before do
      create(:bounced_email, bounce_type: 'hard', bounce_category: 'user_not_found', campaign_id: 'campaign_1')
      create(:bounced_email, bounce_type: 'soft', bounce_category: 'temporary', campaign_id: 'campaign_2')
      create(:bounced_email, bounce_type: 'hard', bounce_category: 'spam_block', campaign_id: nil)
    end

    it 'filters by category' do
      expect(BouncedEmail.by_category('user_not_found').count).to eq(1)
    end

    it 'filters hard bounces' do
      expect(BouncedEmail.hard.count).to eq(2)
    end

    it 'filters by campaign' do
      expect(BouncedEmail.by_campaign('campaign_1').count).to eq(1)
    end

    it 'filters global bounces' do
      expect(BouncedEmail.global.count).to eq(1)
    end
  end
end

