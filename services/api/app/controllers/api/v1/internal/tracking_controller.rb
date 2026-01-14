# frozen_string_literal: true

module Api
  module V1
    module Internal
      class TrackingController < ApplicationController
        # Skip standard API key auth - use internal auth
        skip_before_action :authenticate_api_key
        before_action :verify_internal_request

        # POST /api/v1/internal/tracking_event
        # Receives tracking events from tracking service
        def event
          message_id = params[:message_id]
          event_type = params[:event_type]
          data = params[:data] || {}

          # Find email log
          email_log = EmailLog.find_by(external_message_id: message_id)

          unless email_log
            Rails.logger.warn "Tracking event for unknown message: #{message_id}"
            return render json: { error: 'Message not found' }, status: :not_found
          end

          # Create tracking event
          TrackingEvent.create!(
            email_log: email_log,
            event_type: event_type,
            event_data: data,
            ip_address: data[:ip],
            user_agent: data[:user_agent]
          )

          # Send webhook to AMS if configured
          if SystemConfig.get(:ams_callback_url).present?
            ReportToAmsJob.perform_later(
              email_log.id,
              event_type,
              data
            )
          end

          render json: { success: true }
        rescue StandardError => e
          Rails.logger.error "Tracking event error: #{e.message}"
          render json: { error: e.message }, status: :unprocessable_entity
        end

        private

        def verify_internal_request
          # Check HMAC signature if webhook secret is configured
          webhook_secret = ENV['WEBHOOK_SECRET']

          if webhook_secret.present?
            signature = request.headers['X-Tracking-Signature']
            return unauthorized unless signature.present?

            payload = request.raw_post
            expected = OpenSSL::HMAC.hexdigest('SHA256', webhook_secret, payload)

            unless ActiveSupport::SecurityUtils.secure_compare(signature, expected)
              return unauthorized
            end
          else
            # No secret - check if from Docker network
            return unauthorized unless trusted_source?
          end
        end

        def unauthorized
          Rails.logger.warn "Internal tracking request unauthorized: #{request.remote_ip}"
          render json: { error: 'Unauthorized' }, status: :unauthorized
        end

        def trusted_source?
          remote_ip = request.remote_ip

          trusted_networks = [
            IPAddr.new('172.16.0.0/12'),
            IPAddr.new('10.0.0.0/8'),
            IPAddr.new('192.168.0.0/16'),
            IPAddr.new('127.0.0.1/8')
          ]

          begin
            ip = IPAddr.new(remote_ip)
            trusted_networks.any? { |network| network.include?(ip) }
          rescue IPAddr::InvalidAddressError
            false
          end
        end
      end
    end
  end
end
