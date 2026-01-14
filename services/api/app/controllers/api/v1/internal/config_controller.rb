# frozen_string_literal: true

module Api
  module V1
    module Internal
      class ConfigController < ApplicationController
        # Skip standard API key auth - use internal auth
        skip_before_action :authenticate_api_key
        before_action :verify_internal_request

        # GET /api/v1/internal/smtp_relay_config
        # Returns SMTP Relay configuration
        def smtp_relay
          config = SystemConfig.instance

          render json: {
            secret: config.smtp_relay_secret,
            auth_required: config.smtp_relay_auth_required,
            tls_enabled: config.smtp_relay_tls_enabled,
            domain: config.domain
          }
        end

        # POST /api/v1/internal/smtp_auth
        # Authenticate SMTP credentials against SmtpCredential model
        def smtp_auth
          username = params[:username]
          password = params[:password]

          if username.blank? || password.blank?
            return render json: { success: false, error: 'Missing credentials' }, status: :bad_request
          end

          credential = SmtpCredential.active.find_by(username: username)

          if credential.nil?
            Rails.logger.warn "SMTP auth: Unknown user #{username}"
            return render json: { success: false, error: 'Invalid credentials' }, status: :unauthorized
          end

          unless credential.verify_password(password)
            Rails.logger.warn "SMTP auth: Invalid password for #{username}"
            return render json: { success: false, error: 'Invalid credentials' }, status: :unauthorized
          end

          # Update last used timestamp
          credential.mark_as_used!

          Rails.logger.info "SMTP auth: Success for #{username}"
          render json: {
            success: true,
            username: credential.username,
            rate_limit: credential.rate_limit
          }
        end

        private

        def verify_internal_request
          # Check if request comes from internal Docker network
          unless trusted_source?
            Rails.logger.warn "Internal config request from untrusted source: #{request.remote_ip}"
            render json: { error: 'Unauthorized' }, status: :unauthorized
          end
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
      end
    end
  end
end
