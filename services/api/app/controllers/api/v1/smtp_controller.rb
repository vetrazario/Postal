# frozen_string_literal: true

module Api
  module V1
    class SmtpController < ApplicationController
      # Use separate authentication for SMTP relay
      skip_before_action :authenticate_api_key
      before_action :authenticate_smtp_relay

      # POST /api/v1/smtp/receive
      # Receives parsed email from SMTP Relay
      def receive
        # Log minimal info (no sensitive data - envelope filtered by filter_parameters)
        Rails.logger.info "SMTP receive: envelope present"

        # Validate required fields
        unless valid_smtp_payload?
          return render json: {
            error: 'Invalid payload',
            message: 'Missing required fields: envelope and message'
          }, status: :bad_request
        end

        # Extract data from payload (format from server.js)
        # Convert ActionController::Parameters to Hash
        envelope = params[:envelope].to_unsafe_h
        message = params[:message].to_unsafe_h
        raw = params[:raw]

        # Generate internal message ID
        message_id = generate_message_id

        # Get recipient (first to address)
        recipient = envelope['to'].is_a?(Array) ? envelope['to'].first : envelope['to']

        # Create EmailLog record
        # Extract campaign_id from headers (various formats supported)
        headers = message['headers'] || {}
        campaign_id = headers['x-id-mail'] ||
                      headers['X-ID-mail'] ||
                      headers['X-Id-Mail'] ||
                      headers['x-campaign-id'] ||
                      headers['X-Campaign-ID'] ||
                      headers['x-mailing-id'] ||
                      headers['X-Mailing-ID']
        
        email_log = EmailLog.create!(
          message_id: message_id,
          external_message_id: message['headers']&.dig('message-id'),
          campaign_id: campaign_id,
          recipient: encrypt_email(recipient),
          recipient_masked: mask_email(recipient),
          sender: envelope['from'],
          subject: message['subject'],
          status: 'queued',
          sent_at: nil,
          delivered_at: nil
        )

        # Store email data for background processing
        email_data = {
          email_log_id: email_log.id,
          envelope: {
            from: envelope['from'],
            to: envelope['to']
          },
          message: {
            from: message['from'],
            to: message['to'],
            cc: message['cc'],
            subject: message['subject'],
            text: message['text'],
            html: message['html'],
            headers: message['headers']
          },
          raw: raw
        }

        # Queue background job to send email via Postal
        SendSmtpEmailJob.perform_later(email_data)

        # Return success response
        render json: {
          status: 'queued',
          message_id: message_id,
          email_log_id: email_log.id,
          queued_at: Time.current.iso8601
        }, status: :accepted

      rescue => e
        Rails.logger.error "SMTP receive error: #{e.class.name}"

        render json: {
          error: 'Processing failed',
          message: 'Internal error'
        }, status: :internal_server_error
      end

      private

      def authenticate_smtp_relay
        # SMTP relay must provide valid API key via header
        relay_key = request.headers['X-SMTP-Relay-Key'] || params[:smtp_relay_key]
        expected_key = ENV['SMTP_RELAY_API_KEY']

        # If no key configured, allow internal network only (Docker network)
        if expected_key.blank?
          # Accept requests from internal Docker network (172.x.x.x, 10.x.x.x)
          client_ip = request.remote_ip
          unless client_ip.start_with?('172.', '10.', '127.')
            render json: { error: 'Unauthorized' }, status: :unauthorized
          end
          return
        end

        # Validate key
        unless ActiveSupport::SecurityUtils.secure_compare(relay_key.to_s, expected_key)
          render json: { error: 'Unauthorized' }, status: :unauthorized
        end
      end

      def valid_smtp_payload?
        params[:envelope].present? && params[:message].present?
      end

      def generate_message_id
        "smtp_#{SecureRandom.hex(12)}"
      end

      def encrypt_email(email)
        return email if email.blank?

        # Use symmetric encryption with app secret
        key = Rails.application.secret_key_base[0, 32]
        crypt = ActiveSupport::MessageEncryptor.new(key)
        crypt.encrypt_and_sign(email)
      rescue => e
        Rails.logger.error "Email encryption failed: #{e.class.name}"
        # Return masked version as fallback (never store plaintext)
        mask_email(email)
      end

      def mask_email(email)
        return email unless email.to_s.include?('@')

        local, domain = email.split('@')
        masked_local = local[0] + ('*' * [local.length - 1, 1].max)
        "#{masked_local}@#{domain}"
      end
    end
  end
end
