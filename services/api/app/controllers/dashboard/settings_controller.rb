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

    # Apply changes (restart services)
    def apply_changes
      config = SystemConfig.instance
      services = params[:services] || config.restart_services

      results = {}
      success = true

      services.each do |service|
        result = restart_service(service)
        results[service] = result
        success = false unless result[:success]
      end

      if success
        # Reset restart flag
        config.update_columns(restart_required: false, restart_services: [], changed_fields: {})

        render json: {
          success: true,
          message: "Services restarted: #{services.join(', ')}",
          results: results
        }
      else
        render json: {
          success: false,
          message: 'Some services failed to restart',
          results: results
        }, status: :unprocessable_entity
      end
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

        # Limits
        :daily_limit,
        :sidekiq_concurrency,
        :webhook_secret
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
      else
        { success: false, error: "Unknown service: #{service}" }
      end
    end

    def restart_docker_service(service)
      # Docker CLI path
      docker_cmd = `which docker 2>/dev/null`.strip
      docker_cmd = '/usr/bin/docker' if docker_cmd.empty?

      # Use mounted docker-compose.yml file
      compose_file = '/project/docker-compose.yml'

      unless File.exist?(compose_file)
        return {
          service: service,
          success: false,
          error: "docker-compose.yml not found at #{compose_file}"
        }
      end

      # Execute docker compose restart with explicit file path
      command = "#{docker_cmd} compose -f #{compose_file} restart #{service}"

      Rails.logger.info "Executing: #{command}"
      output = `#{command} 2>&1`
      success = $?.success?

      Rails.logger.info "Result: success=#{success}, output=#{output}"

      {
        service: service,
        success: success,
        message: success ? 'Restarted successfully' : output
      }
    rescue => e
      Rails.logger.error "Restart error: #{e.class}: #{e.message}"
      {
        service: service,
        success: false,
        error: "#{e.class}: #{e.message}"
      }
    end
  end
end
