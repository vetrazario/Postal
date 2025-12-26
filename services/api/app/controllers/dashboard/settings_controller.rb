# frozen_string_literal: true

module Dashboard
  class SettingsController < BaseController
    def show
      @ai_settings = AiSetting.instance
    end

    def update
      @ai_settings = AiSetting.instance

      if @ai_settings.update(ai_settings_params)
        redirect_to dashboard_settings_path, notice: 'Settings updated successfully'
      else
        render :show
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
  end
end
