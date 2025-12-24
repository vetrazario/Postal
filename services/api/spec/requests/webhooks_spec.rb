require 'rails_helper'
require_relative '../../app/lib/encrypto_signo'

RSpec.describe "Webhooks", type: :request do
  describe "POST /api/v1/webhook" do
    let(:private_key) { OpenSSL::PKey::RSA.new(2048) }
    let(:public_key) { private_key.public_key }
    let(:public_key_pem) { public_key.to_pem }
    
    let(:raw_body) do
      {
        event: "MessageDelivered",
        payload: {
          message: {
            id: "12345",
            token: "abc123"
          }
        }
      }.to_json
    end
    
    let(:signature) { EncryptoSigno.sign(private_key, raw_body) }
    
    let(:email_log) do
      create(:email_log, postal_message_id: "12345", status: 'sent')
    end

    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:[]).with('POSTAL_WEBHOOK_PUBLIC_KEY').and_return(public_key_pem)
      allow(ENV).to receive(:fetch).with('POSTAL_WEBHOOK_PUBLIC_KEY', anything).and_return(public_key_pem)
      
      email_log # Создаем email_log перед запросом
    end

    context "with valid signature" do
      it "returns 200 and processes the webhook" do
        post "/api/v1/webhook",
          params: {},
          headers: {
            "Content-Type" => "application/json",
            "X-Postal-Signature" => signature
          },
          env: { 'RAW_POST_DATA' => raw_body }
        
        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["received"]).to eq(true)
        
        email_log.reload
        expect(email_log.status).to eq("delivered")
      end

      it "handles MessageBounced event" do
        bounced_body = {
          event: "MessageBounced",
          payload: {
            message: {
              id: "12345"
            }
          }
        }.to_json
        
        bounced_signature = EncryptoSigno.sign(private_key, bounced_body)
        
        post "/api/v1/webhook",
          params: {},
          headers: {
            "Content-Type" => "application/json",
            "X-Postal-Signature" => bounced_signature
          },
          env: { 'RAW_POST_DATA' => bounced_body }
        
        expect(response).to have_http_status(:ok)
        
        email_log.reload
        expect(email_log.status).to eq("bounced")
      end

      it "handles MessageHeld event" do
        held_body = {
          event: "MessageHeld",
          payload: {
            message: {
              id: "12345"
            }
          }
        }.to_json
        
        held_signature = EncryptoSigno.sign(private_key, held_body)
        
        post "/api/v1/webhook",
          params: {},
          headers: {
            "Content-Type" => "application/json",
            "X-Postal-Signature" => held_signature
          },
          env: { 'RAW_POST_DATA' => held_body }
        
        expect(response).to have_http_status(:ok)
        
        email_log.reload
        expect(email_log.status).to eq("failed")
      end
    end

    context "with invalid signature" do
      it "returns 401 Unauthorized" do
        invalid_signature = "invalid_signature_here"
        
        post "/api/v1/webhook",
          params: {},
          headers: {
            "Content-Type" => "application/json",
            "X-Postal-Signature" => invalid_signature
          },
          env: { 'RAW_POST_DATA' => raw_body }
        
        expect(response).to have_http_status(:unauthorized)
      end

      it "returns 401 when signature is empty" do
        post "/api/v1/webhook",
          params: {},
          headers: {
            "Content-Type" => "application/json",
            "X-Postal-Signature" => ""
          },
          env: { 'RAW_POST_DATA' => raw_body }
        
        expect(response).to have_http_status(:unauthorized)
      end

      it "returns 401 when signature is missing" do
        post "/api/v1/webhook",
          params: {},
          headers: {
            "Content-Type" => "application/json"
          },
          env: { 'RAW_POST_DATA' => raw_body }
        
        expect(response).to have_http_status(:unauthorized)
      end

      it "returns 401 when signature is for different body" do
        different_body = { event: "DifferentEvent" }.to_json
        different_signature = EncryptoSigno.sign(private_key, different_body)
        
        post "/api/v1/webhook",
          params: {},
          headers: {
            "Content-Type" => "application/json",
            "X-Postal-Signature" => different_signature
          },
          env: { 'RAW_POST_DATA' => raw_body }
        
        expect(response).to have_http_status(:unauthorized)
      end

      it "returns 401 when signature is from different key" do
        other_private_key = OpenSSL::PKey::RSA.new(2048)
        other_signature = EncryptoSigno.sign(other_private_key, raw_body)
        
        post "/api/v1/webhook",
          params: {},
          headers: {
            "Content-Type" => "application/json",
            "X-Postal-Signature" => other_signature
          },
          env: { 'RAW_POST_DATA' => raw_body }
        
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when public key is not configured" do
      it "returns 401 Unauthorized" do
        allow(ENV).to receive(:[]).with('POSTAL_WEBHOOK_PUBLIC_KEY').and_return('')
        allow(ENV).to receive(:fetch).with('POSTAL_WEBHOOK_PUBLIC_KEY', anything).and_return('')
        
        post "/api/v1/webhook",
          params: {},
          headers: {
            "Content-Type" => "application/json",
            "X-Postal-Signature" => signature
          },
          env: { 'RAW_POST_DATA' => raw_body }
        
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when public key is invalid" do
      it "returns 401 Unauthorized" do
        allow(ENV).to receive(:[]).with('POSTAL_WEBHOOK_PUBLIC_KEY').and_return('invalid_key')
        allow(ENV).to receive(:fetch).with('POSTAL_WEBHOOK_PUBLIC_KEY', anything).and_return('invalid_key')
        
        post "/api/v1/webhook",
          params: {},
          headers: {
            "Content-Type" => "application/json",
            "X-Postal-Signature" => signature
          },
          env: { 'RAW_POST_DATA' => raw_body }
        
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when email log is not found" do
      it "returns 200 but does not process" do
        body_with_unknown_id = {
          event: "MessageDelivered",
          payload: {
            message: {
              id: "unknown_id"
            }
          }
        }.to_json
        
        unknown_signature = EncryptoSigno.sign(private_key, body_with_unknown_id)
        
        post "/api/v1/webhook",
          params: {},
          headers: {
            "Content-Type" => "application/json",
            "X-Postal-Signature" => unknown_signature
          },
          env: { 'RAW_POST_DATA' => body_with_unknown_id }
        
        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["received"]).to eq(true)
      end
    end
  end
end
