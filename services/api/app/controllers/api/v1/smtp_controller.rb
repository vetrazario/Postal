# frozen_string_literal: true

module Api
  module V1
    class SmtpController < ApplicationController
      # POST /api/v1/smtp/receive
      # Receives parsed email from Haraka SMTP Relay
      def receive
        # Validate required fields
        unless valid_smtp_payload?
          return render json: {
            error: 'Invalid payload',
            message: 'Missing required fields: envelope, headers, or body'
          }, status: :bad_request
        end

        # Extract data from payload
        envelope = params[:envelope]
        headers = params[:headers]
        body = params[:body]
        attachments = params[:attachments] || []
        tracking = params[:tracking] || {}
        metadata = params[:metadata] || {}

        # Generate internal message ID if not provided
        message_id = tracking[:message_id] || generate_message_id

        # Create EmailLog record
        email_log = EmailLog.create!(
          message_id: message_id,
          external_message_id: tracking[:original_message_id],
          campaign_id: tracking[:campaign_id],
          recipient: encrypt_email(envelope[:to].first),
          recipient_masked: mask_email(envelope[:to].first),
          sender: headers[:from],
          subject: headers[:subject],
          status: 'queued',
          sent_at: nil,
          delivered_at: nil
        )

        # Store email data for background processing
        email_data = {
          email_log_id: email_log.id,
          envelope: envelope,
          headers: headers,
          body: body,
          attachments: attachments,
          tracking: tracking,
          metadata: metadata
        }

        # Queue background job to send email
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
        params[:envelope].present? &&
          params[:headers].present? &&
          params[:body].present?
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
