# frozen_string_literal: true

require 'fileutils'

module Dashboard
  class MailingRulesController < BaseController
    def show
      @rule = MailingRule.instance
    end

    def update
      @rule = MailingRule.instance

      if @rule.update(mailing_rule_params)
        redirect_to dashboard_mailing_rules_path, notice: 'Mailing rules updated successfully'
      else
        render :show
      end
    end

    def test_ams_connection
      # Берём данные из params (форма), если они есть, иначе из сохранённых настроек
      url = params.dig(:mailing_rule, :ams_api_url)&.presence
      key = params.dig(:mailing_rule, :ams_api_key)&.presence

      @rule = MailingRule.instance
      url ||= @rule.ams_api_url
      key ||= @rule.ams_api_key

      unless url.present? && key.present?
        render json: { success: false, error: 'AMS API URL and Key must be configured' }, status: :bad_request
        return
      end

      begin
        client = AmsClient.new(
          api_url: url,
          api_key: key
        )

        result = client.test_connection

        if result[:success]
          render json: { success: true, message: result[:message] || 'Connection successful' }
        else
          render json: { success: false, error: result[:error] || 'Connection failed' }, status: :bad_request
        end
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :bad_request
      end
    end

    # Download current bounce patterns configuration
    def download_bounce_patterns
      config_path = Rails.root.join('config', 'bounce_patterns.yml')

      unless File.exist?(config_path)
        redirect_to dashboard_mailing_rules_path, alert: 'Bounce patterns file not found'
        return
      end

      send_file config_path,
                filename: "bounce_patterns_#{Time.current.to_i}.yml",
                type: 'application/x-yaml',
                disposition: 'attachment'
    end

    # Upload new bounce patterns configuration
    def upload_bounce_patterns
      uploaded_file = params[:bounce_patterns_file]

      unless uploaded_file
        redirect_to dashboard_mailing_rules_path, alert: 'No file selected'
        return
      end

      # Check file size (max 1MB for config file)
      if uploaded_file.size > 1.megabyte
        redirect_to dashboard_mailing_rules_path, alert: 'File too large. Maximum size is 1MB.'
        return
      end

      begin
        # Validate YAML
        yaml_content = uploaded_file.read
        parsed = YAML.safe_load(yaml_content)

        # Check structure
        unless parsed.is_a?(Hash) && parsed['patterns'].is_a?(Hash)
          raise 'Invalid file structure. Must contain "patterns" key.'
        end

        # Create backup of current file
        config_path = Rails.root.join('config', 'bounce_patterns.yml')
        backup_path = Rails.root.join('config', "bounce_patterns.backup.#{Time.current.to_i}.yml")
        FileUtils.cp(config_path, backup_path) if File.exist?(config_path)

        # Save new file
        File.write(config_path, yaml_content)

        # Reload config in ErrorClassifier
        ErrorClassifier.reload_config!

        redirect_to dashboard_mailing_rules_path,
                    notice: "Bounce patterns updated successfully. Backup saved to #{backup_path.basename}"
      rescue StandardError => e
        redirect_to dashboard_mailing_rules_path,
                    alert: "Failed to upload: #{e.message}"
      end
    end

    # Reset bounce patterns to defaults
    def reset_bounce_patterns
      begin
        config_path = Rails.root.join('config', 'bounce_patterns.yml')

        # Create backup of current file
        if File.exist?(config_path)
          backup_path = Rails.root.join('config', "bounce_patterns.backup.#{Time.current.to_i}.yml")
          FileUtils.cp(config_path, backup_path)
        end

        # Restore default config
        default_path = Rails.root.join('config', 'bounce_patterns.default.yml')
        default_content = File.read(default_path)
        File.write(config_path, default_content)

        # Reload config
        ErrorClassifier.reload_config!

        redirect_to dashboard_mailing_rules_path,
                    notice: 'Bounce patterns reset to defaults'
      rescue StandardError => e
        redirect_to dashboard_mailing_rules_path,
                    alert: "Failed to reset: #{e.message}"
      end
    end

    private

    def mailing_rule_params
      params.require(:mailing_rule).permit(
        :name,
        :active,
        :max_bounce_rate,
        :max_rate_limit_errors,
        :max_spam_blocks,
        :check_window_minutes,
        :auto_stop_mailing,
        :notify_email,
        :notification_email,
        :ams_api_url,
        :ams_api_key
      )
    end
  end
end

