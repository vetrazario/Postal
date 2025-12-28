# frozen_string_literal: true

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

