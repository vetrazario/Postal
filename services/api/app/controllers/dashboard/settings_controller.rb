# frozen_string_literal: true

module Dashboard
  class SettingsController < BaseController
    def show
      @ai_settings = AiSetting.instance
      @system_config = SystemConfig.instance
      @total_cost = @ai_settings.total_estimated_cost
    end

    # AI Settings (existing)
    def update
      @ai_settings = AiSetting.instance

      if @ai_settings.update(ai_settings_params)
        redirect_to dashboard_settings_path, notice: 'AI settings updated successfully'
      else
        @system_config = SystemConfig.instance
        render :show
      end
    end

    # System Configuration (new)
    def update_system_config
      @system_config = SystemConfig.instance

      if @system_config.update(system_config_params)
        # Sync to .env file
        @system_config.sync_to_env_file

        if @system_config.restart_required?
          flash[:warning] = "Configuration updated. Services need restart: #{@system_config.restart_services.join(', ')}"
          flash[:restart_services] = @system_config.restart_services
        else
          flash[:notice] = 'Configuration updated successfully'
        end

        redirect_to dashboard_settings_path
      else
        @ai_settings = AiSetting.instance
        flash.now[:error] = @system_config.errors.full_messages.join(', ')
        render :show
      end
    end

    # Test AMS connection
    def test_ams_connection
      config = SystemConfig.instance
      result = config.test_ams_connection

      render json: result
    end

    # Test Postal connection
    def test_postal_connection
      config = SystemConfig.instance
      result = config.test_postal_connection

      render json: result
    end

    # Test SMTP Relay connection
    def test_smtp_relay_connection
      config = SystemConfig.instance
      result = config.test_smtp_relay_connection

      render json: result
    end

    # Generate new SMTP Relay credentials
    # NOTE: SMTP credentials are now managed via SmtpCredential model
    # This action creates a new credential and returns the details
    def generate_smtp_credentials
      # Generate a new SMTP credential
      smtp_credential, password = SmtpCredential.generate(
        description: 'Auto-generated credential',
        rate_limit: 100
      )

      render json: {
        success: true,
        credentials: {
          username: smtp_credential.username,
          password: password,
          id: smtp_credential.id
        },
        message: 'New SMTP credential generated. See SMTP Credentials page for details.'
      }
    rescue StandardError => e
      render json: { success: false, error: e.message }, status: :unprocessable_entity
    end

    # Apply changes (restart services)
    def apply_changes
      config = SystemConfig.instance
      services = params[:services] || config.restart_services

      # Reset restart flag - actual restart must be done manually via:
      # docker compose restart api sidekiq
      config.update_columns(restart_required: false, restart_services: [], changed_fields: {})

      render json: {
        success: true,
        message: "Configuration applied. Please restart services manually: docker compose restart #{services.join(' ')}",
        services: services
      }
    end

    private

    def ai_settings_params
      params.require(:ai_setting).permit(
        :openrouter_api_key,
        :ai_model,
        :temperature,
        :max_tokens,
        :enabled
      )
    end

    def system_config_params
      params.require(:system_config).permit(
        # Server
        :domain,
        :allowed_sender_domains,
        :cors_origins,

        # AMS
        :ams_callback_url,
        :ams_api_key,
        :ams_api_url,

        # Postal
        :postal_api_url,
        :postal_api_key,
        :postal_signing_key,
        :postal_webhook_public_key,

        # Limits
        :daily_limit,
        :sidekiq_concurrency,
        :webhook_secret,

        # SMTP Relay (credentials managed via SMTP Credentials page)
        :smtp_relay_secret,
        :smtp_relay_port,
        :smtp_relay_auth_required,
        :smtp_relay_tls_enabled,

        # Sidekiq Web UI
        :sidekiq_web_username,
        :sidekiq_web_password,

        # Logging
        :log_level,
        :sentry_dsn,

        # Let's Encrypt
        :letsencrypt_email
      )
    end

    def restart_service(service)
      case service
      when 'api'
        restart_docker_service('api')
      when 'sidekiq'
        restart_docker_service('sidekiq')
      when 'postal'
        restart_docker_service('postal')
      when 'smtp-relay'
        restart_docker_service('smtp-relay')
      else
        { success: false, error: "Unknown service: #{service}" }
      end
    end

    def restart_docker_service(service)
    # БЕЗОПАСНОСТЬ: Функция отключена - требовался Docker socket
    # Для рестарта используйте: docker compose restart <service>
    Rails.logger.warn "restart_docker_service called but disabled for security"
    return {
      service: service,
      success: false,
      error: "Function disabled: Docker socket removed for security. Use 'docker compose restart' manually."
    }
      # Whitelist of allowed services (defense in depth)
      allowed_services = %w[api sidekiq postal]
      unless allowed_services.include?(service)
        return { service: service, success: false, error: "Service not allowed: #{service}" }
      end

      # Docker CLI path
      docker_cmd = '/usr/bin/docker'

      # Use mounted docker-compose.yml file
      compose_file = '/project/docker-compose.yml'

      unless File.exist?(compose_file)
        return {
          service: service,
          success: false,
          error: "docker-compose.yml not found at #{compose_file}"
        }
      end

      # Use Open3 with array args to prevent shell injection
      require 'open3'
      args = [docker_cmd, 'compose', '-f', compose_file, 'restart', service]

      Rails.logger.info "Executing: #{args.join(' ')}"
      stdout, stderr, status = Open3.capture3(*args)
      success = status.success?
      output = stdout.presence || stderr

      Rails.logger.info "Result: success=#{success}, output=#{output}"

      {
        service: service,
        success: success,
        message: success ? 'Restarted successfully' : output
      }
    rescue StandardError => e
      Rails.logger.error "Restart error: #{e.class}: #{e.message}"
      {
        service: service,
        success: false,
        error: "#{e.class}: #{e.message}"
      }
    end
  end
end
