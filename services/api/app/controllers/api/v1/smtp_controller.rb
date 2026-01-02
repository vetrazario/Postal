# frozen_string_literal: true

module Api
  module V1
    class SmtpController < ApplicationController
      # Skip API key authentication - use HMAC signature instead
      skip_before_action :authenticate_api_key
      before_action :verify_smtp_relay_request

      # Rate limiting for SMTP endpoint
      SMTP_RATE_LIMIT = 100 # requests per minute
      SMTP_RATE_WINDOW = 60 # seconds

      # POST /api/v1/smtp/receive
      # Receives parsed email from SMTP Relay
      def receive
        # Log incoming payload (without sensitive data)
        Rails.logger.info "SMTP receive from #{request.remote_ip}: envelope=#{params[:envelope]&.keys}"

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
        # Extract campaign_id from headers (AMS sends it as X-Campaign-ID or x-campaign-id)
        campaign_id = message['headers']&.dig('x-campaign-id') || 
                      message['headers']&.dig('X-Campaign-ID') ||
                      message['headers']&.dig('x-mailing-id') ||
                      message['headers']&.dig('X-Mailing-ID')
        
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
        Rails.logger.error "SMTP receive error: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")

        render json: {
          error: 'Processing failed',
          message: e.message
        }, status: :internal_server_error
      end

      private

      # Verify the request comes from authorized SMTP relay
      def verify_smtp_relay_request
        # Check if SMTP relay secret is configured
        smtp_secret = ENV['SMTP_RELAY_SECRET']

        if smtp_secret.present?
          # Verify HMAC signature
          unless verify_hmac_signature(smtp_secret)
            Rails.logger.warn "SMTP endpoint: Invalid HMAC signature from #{request.remote_ip}"
            render json: { error: 'Unauthorized', message: 'Invalid signature' }, status: :unauthorized
            return
          end
        else
          # No secret configured - check if request comes from internal Docker network
          unless trusted_source?
            Rails.logger.warn "SMTP endpoint: Request from untrusted source #{request.remote_ip}"
            render json: { error: 'Unauthorized', message: 'Access denied' }, status: :unauthorized
            return
          end
        end

        # Rate limiting
        unless within_rate_limit?
          Rails.logger.warn "SMTP endpoint: Rate limit exceeded for #{request.remote_ip}"
          render json: { error: 'Rate limit exceeded', retry_after: SMTP_RATE_WINDOW }, status: :too_many_requests
        end
      end

      def verify_hmac_signature(secret)
        signature = request.headers['X-SMTP-Relay-Signature']
        timestamp = request.headers['X-SMTP-Relay-Timestamp']

        return false if signature.blank? || timestamp.blank?

        # Check timestamp is not too old (5 minutes)
        request_time = timestamp.to_i
        return false if (Time.now.to_i - request_time / 1000).abs > 300

        # Reconstruct payload for verification
        payload = {
          envelope: params[:envelope]&.to_unsafe_h,
          message: params[:message]&.to_unsafe_h,
          raw: params[:raw],
          timestamp: timestamp
        }

        expected_signature = OpenSSL::HMAC.hexdigest('SHA256', secret, payload.to_json)
        ActiveSupport::SecurityUtils.secure_compare(signature, expected_signature)
      end

      def trusted_source?
        remote_ip = request.remote_ip

        # Allow requests from Docker internal networks
        trusted_networks = [
          IPAddr.new('172.16.0.0/12'),   # Docker default bridge
          IPAddr.new('10.0.0.0/8'),       # Docker overlay
          IPAddr.new('192.168.0.0/16'),   # Docker host
          IPAddr.new('127.0.0.1/8')       # Localhost
        ]

        begin
          ip = IPAddr.new(remote_ip)
          trusted_networks.any? { |network| network.include?(ip) }
        rescue IPAddr::InvalidAddressError
          false
        end
      end

      def within_rate_limit?
        cache_key = "smtp_rate_limit:#{request.remote_ip}"
        count = Rails.cache.increment(cache_key, 1, expires_in: SMTP_RATE_WINDOW.seconds, initial: 0)
        count <= SMTP_RATE_LIMIT
      end

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
