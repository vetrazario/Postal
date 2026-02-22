# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PostalClient do
  let(:api_url) { 'http://postal.test:5000' }
  let(:api_key) { 'test_postal_api_key' }
  let(:client) { described_class.new(api_url: api_url, api_key: api_key) }

  before do
    allow(SystemConfig).to receive(:get).with(:domain).and_return('test.example.com')
  end

  describe '#send_message' do
    context 'when Postal API returns success' do
      before do
        stub_request(:post, "#{api_url}/api/v1/send/message")
          .with(
            headers: {
              'Host' => 'test.example.com',
              'X-Server-API-Key' => api_key,
              'Content-Type' => 'application/json'
            }
          )
          .to_return(
            status: 200,
            body: {
              data: {
                messages: {
                  'recipient@example.com' => { id: 'postal_123', token: 'tok_abc' }
                }
              }
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns success with message_id' do
        result = client.send_message(
          to: 'recipient@example.com',
          from: 'sender@example.com',
          subject: 'Test',
          html_body: '<p>Hello</p>'
        )

        expect(result).to eq(success: true, message_id: 'postal_123', token: 'tok_abc')
      end

      it 'sends correct payload to Postal' do
        client.send_message(
          to: 'recipient@example.com',
          from: 'sender@example.com',
          subject: 'Test Subject',
          html_body: '<p>Body</p>'
        )

        expect(WebMock).to have_requested(:post, "#{api_url}/api/v1/send/message")
          .with { |req|
            body = JSON.parse(req.body)
            body['to'] == ['recipient@example.com'] &&
              body['from'] == 'sender@example.com' &&
              body['subject'] == 'Test Subject' &&
              body['html_body'] == '<p>Body</p>'
          }
      end
    end

    context 'when Postal API returns error' do
      before do
        stub_request(:post, "#{api_url}/api/v1/send/message")
          .to_return(
            status: 422,
            body: { error: 'Invalid recipient' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns failure with error message' do
        result = client.send_message(
          to: 'bad@example.com',
          from: 'sender@example.com',
          subject: 'Test',
          html_body: '<p>Hi</p>'
        )

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Invalid recipient')
      end
    end

    context 'when network error occurs' do
      before do
        stub_request(:post, "#{api_url}/api/v1/send/message")
          .to_raise(StandardError.new('Connection refused'))
      end

      it 'returns failure with error message' do
        result = client.send_message(
          to: 'user@example.com',
          from: 'sender@example.com',
          subject: 'Test',
          html_body: '<p>Hi</p>'
        )

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Connection refused')
      end
    end
  end

  describe '#mask_email' do
    it 'masks email for logging' do
      expect(client.send(:mask_email, 'user@example.com')).to match(/\A.+\*\*\*@.+\z/)
    end

    it 'returns email unchanged when no @' do
      expect(client.send(:mask_email, 'invalid')).to eq('invalid')
    end
  end
end
