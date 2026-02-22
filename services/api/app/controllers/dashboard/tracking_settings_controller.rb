# frozen_string_literal: true

module Dashboard
  class TrackingSettingsController < BaseController
    def show
      # Load current settings from SystemConfig (keys: enable_open_tracking, enable_click_tracking)
      @tracking_settings = {
        enable_open_tracking: SystemConfig.get(:enable_open_tracking) != false,
        enable_click_tracking: SystemConfig.get(:enable_click_tracking) != false
      }
    end

    def update
      permitted = params.permit(tracking_settings: [:enable_open_tracking, :enable_click_tracking])[:tracking_settings] || {}

      open_val = permitted[:enable_open_tracking].present? ? ActiveModel::Type::Boolean.new.cast(permitted[:enable_open_tracking]) : false
      click_val = permitted[:enable_click_tracking].present? ? ActiveModel::Type::Boolean.new.cast(permitted[:enable_click_tracking]) : false
      SystemConfig.set(:enable_open_tracking, open_val)
      SystemConfig.set(:enable_click_tracking, click_val)

      flash[:notice] = 'Tracking settings updated successfully'
      redirect_to dashboard_tracking_settings_path
    end
  end
end
