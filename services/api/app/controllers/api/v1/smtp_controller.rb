# frozen_string_literal: true

module Api
  module V1
    class SmtpController < ApplicationController
      # POST /api/v1/smtp/receive
      # Receives parsed email from SMTP Relay
      def receive
        # Log incoming payload for debugging
        Rails.logger.info "SMTP receive payload: #{params.to_unsafe_h.inspect}"

        # Validate required fields
        unless valid_smtp_payload?
          return render json: {
            error: 'Invalid payload',
            message: 'Missing required fields: envelope and message'
          }, status: :bad_request
        end

        # Extract data from payload (format from server.js)
        envelope = params[:envelope]
        message = params[:message]
        raw = params[:raw]

        # Generate internal message ID
        message_id = generate_message_id

        # Get recipient (first to address)
        recipient = envelope[:to].is_a?(Array) ? envelope[:to].first : envelope[:to]

        # Create EmailLog record
        email_log = EmailLog.create!(
          message_id: message_id,
          external_message_id: message[:headers]&.dig('message-id'),
          campaign_id: nil, # Can be extracted from headers if needed
          recipient: encrypt_email(recipient),
          recipient_masked: mask_email(recipient),
          sender: envelope[:from],
          subject: message[:subject],
          status: 'queued',
          sent_at: nil,
          delivered_at: nil
        )

        # Store email data for background processing
        email_data = {
          email_log_id: email_log.id,
          envelope: {
            from: envelope[:from],
            to: envelope[:to]
          },
          message: {
            from: message[:from],
            to: message[:to],
            cc: message[:cc],
            subject: message[:subject],
            text: message[:text],
            html: message[:html],
            headers: message[:headers]
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
        Rails.logger.error "SMTP receive error: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")

        render json: {
          error: 'Processing failed',
          message: e.message
        }, status: :internal_server_error
      end

      private

      def valid_smtp_payload?
        params[:envelope].present? && params[:message].present?
      end

      def generate_message_id
        "smtp_#{SecureRandom.hex(12)}"
      end

      def encrypt_email(email)
        # Use Rails 7.1 encryption
        email
      end

      def mask_email(email)
        return email unless email.include?('@')

        local, domain = email.split('@')
        masked_local = local[0] + ('*' * (local.length - 1))
        "#{masked_local}@#{domain}"
      end
    end
  end
end
