# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lib/tracking_handler'

RSpec.describe TrackingHandler do
  let(:database_url) { ENV.fetch('DATABASE_URL', 'postgres://email_sender:test_password@localhost:5432/email_sender_test') }
  let(:redis_url) { ENV.fetch('REDIS_URL', 'redis://localhost:6379/0') }
  let(:handler) { described_class.new(database_url: database_url, redis_url: redis_url) }

  describe '#handle_open' do
    it 'returns success: false when eid is blank' do
      result = handler.handle_open(eid: '', cid: 'x', mid: 'y', ip: '1.2.3.4', user_agent: 'Test')

      expect(result).to eq(success: false)
    end

    it 'returns success: false when cid is blank' do
      eid = Base64.urlsafe_encode64('user@example.com')
      result = handler.handle_open(eid: eid, cid: '', mid: 'y', ip: '1.2.3.4', user_agent: 'Test')

      expect(result).to eq(success: false)
    end

    it 'returns success: true for bot user agent without DB hit' do
      eid = Base64.urlsafe_encode64('user@example.com')
      cid = Base64.urlsafe_encode64('camp_1')
      mid = Base64.urlsafe_encode64('msg_1')

      result = handler.handle_open(
        eid: eid, cid: cid, mid: mid,
        ip: '1.2.3.4',
        user_agent: 'Googlebot/2.1'
      )

      expect(result).to eq(success: true)
    end
  end

  describe '#handle_click' do
    it 'returns success: false when url is blank' do
      eid = Base64.urlsafe_encode64('user@example.com')
      cid = Base64.urlsafe_encode64('camp_1')
      mid = Base64.urlsafe_encode64('msg_1')

      result = handler.handle_click(
        url: '', eid: eid, cid: cid, mid: mid,
        ip: '1.2.3.4', user_agent: 'Test'
      )

      expect(result[:success]).to be false
      expect(result[:url]).to be_nil
    end

    it 'blocks javascript: URLs' do
      url = Base64.urlsafe_encode64('javascript:alert(1)')
      eid = Base64.urlsafe_encode64('user@example.com')
      cid = Base64.urlsafe_encode64('camp_1')
      mid = Base64.urlsafe_encode64('msg_1')

      result = handler.handle_click(
        url: url, eid: eid, cid: cid, mid: mid,
        ip: '1.2.3.4', user_agent: 'Test'
      )

      expect(result[:success]).to be false
      expect(result[:error]).to eq('Invalid redirect URL')
    end

    it 'blocks data: URLs' do
      url = Base64.urlsafe_encode64('data:text/html,<script>alert(1)</script>')
      eid = Base64.urlsafe_encode64('user@example.com')
      cid = Base64.urlsafe_encode64('camp_1')
      mid = Base64.urlsafe_encode64('msg_1')

      result = handler.handle_click(
        url: url, eid: eid, cid: cid, mid: mid,
        ip: '1.2.3.4', user_agent: 'Test'
      )

      expect(result[:success]).to be false
    end

    it 'blocks internal IP URLs' do
      url = Base64.urlsafe_encode64('http://127.0.0.1/admin')
      eid = Base64.urlsafe_encode64('user@example.com')
      cid = Base64.urlsafe_encode64('camp_1')
      mid = Base64.urlsafe_encode64('msg_1')

      result = handler.handle_click(
        url: url, eid: eid, cid: cid, mid: mid,
        ip: '1.2.3.4', user_agent: 'Test'
      )

      expect(result[:success]).to be false
    end
  end

  describe '#handle_unsubscribe' do
    it 'returns success: false when eid is blank' do
      result = handler.handle_unsubscribe(
        eid: '', cid: 'x',
        ip: '1.2.3.4', user_agent: 'Test'
      )

      expect(result[:success]).to be false
      expect(result[:error]).to eq('Missing parameters')
    end

    it 'returns success: false when params are invalid' do
      result = handler.handle_unsubscribe(
        eid: 'not-valid-base64!!!', cid: 'x',
        ip: '1.2.3.4', user_agent: 'Test'
      )

      expect(result[:success]).to be false
      expect(result[:error]).to eq('Invalid parameters')
    end
  end
end
