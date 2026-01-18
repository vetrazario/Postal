# frozen_string_literal: true

module Dashboard
  class TrackingSettingsController < BaseController
    def show
      # Load current settings from SystemConfig or defaults
      @tracking_settings = {
        enable_open_tracking: SystemConfig.get(:tracking_enable_opens) != false,
        enable_click_tracking: SystemConfig.get(:tracking_enable_clicks) != false
      }
    end

    def update
      settings = params[:tracking_settings] || {}
      
      # Update SystemConfig (if we add these fields later)
      # For now, tracking is always enabled via Postal API flags
      
      flash[:notice] = 'Tracking settings updated successfully'
      redirect_to dashboard_tracking_settings_path
    end
  end
end
