# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ErrorClassifier do
  describe '.classify' do
    context 'when classifying Gmail rate limit' do
      it 'returns rate_limit category and should_stop_mailing' do
        payload = {
          output: '421 4.7.0 receiving mail at a rate',
          details: 'rate limited'
        }
        result = ErrorClassifier.classify(payload)
        
        expect(result[:category]).to eq(:rate_limit)
        expect(result[:bounce_type]).to eq('hard')
        expect(result[:should_add_to_bounce]).to be(false)
        expect(result[:should_stop_mailing]).to be(true)
      end
    end

    context 'when classifying Gmail mailbox full' do
      it 'returns mailbox_full category and should_add_to_bounce' do
        payload = {
          output: '550 5.2.1 mailbox is full',
          details: 'over quota'
        }
        result = ErrorClassifier.classify(payload)
        
        expect(result[:category]).to eq(:mailbox_full)
        expect(result[:bounce_type]).to eq('hard')
        expect(result[:should_add_to_bounce]).to be(true)
        expect(result[:should_stop_mailing]).to be(true)
      end
    end

    context 'when classifying user not found' do
      it 'returns user_not_found category and should_add_to_bounce' do
        payload = {
          output: '550 5.1.1 The email account does not exist',
          details: 'user unknown'
        }
        result = ErrorClassifier.classify(payload)
        
        expect(result[:category]).to eq(:user_not_found)
        expect(result[:bounce_type]).to eq('hard')
        expect(result[:should_add_to_bounce]).to be(true)
        expect(result[:should_stop_mailing]).to be(false)
      end
    end

    context 'when classifying spam block' do
      it 'returns spam_block category and should_add_to_bounce' do
        payload = {
          output: '550 5.7.1 message has been blocked',
          details: 'likely spam'
        }
        result = ErrorClassifier.classify(payload)
        
        expect(result[:category]).to eq(:spam_block)
        expect(result[:bounce_type]).to eq('hard')
        expect(result[:should_add_to_bounce]).to be(true)
        expect(result[:should_stop_mailing]).to be(true)
      end
    end

    context 'when classifying temporary error' do
      it 'returns temporary category and should_not_add_to_bounce' do
        payload = {
          output: '421 4.7.0 Temporary System Problem',
          details: 'try again later'
        }
        result = ErrorClassifier.classify(payload)
        
        expect(result[:category]).to eq(:temporary)
        expect(result[:bounce_type]).to eq('hard')
        expect(result[:should_add_to_bounce]).to be(false)
        expect(result[:should_stop_mailing]).to be(true)
      end
    end

    context 'when classifying connection error' do
      it 'returns connection category and should_not_add_to_bounce' do
        payload = {
          output: 'connection refused',
          details: 'timeout'
        }
        result = ErrorClassifier.classify(payload)
        
        expect(result[:category]).to eq(:connection)
        expect(result[:bounce_type]).to eq('hard')
        expect(result[:should_add_to_bounce]).to be(false)
        expect(result[:should_stop_mailing]).to be(true)
      end
    end

    context 'when extracting SMTP code' do
      it 'extracts 3-digit SMTP code' do
        payload = {
          output: '550 5.1.1 The email account does not exist',
          details: ''
        }
        result = ErrorClassifier.classify(payload)
        
        expect(result[:smtp_code]).to eq('550')
      end
    end
  end
end


