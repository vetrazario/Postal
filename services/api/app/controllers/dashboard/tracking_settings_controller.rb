class Dashboard::TrackingSettingsController < Dashboard::BaseController
  def show
    @tracking_settings = load_tracking_settings
    @reputation = DomainReputationChecker.new.check_all
    @throttle_info = EmailThrottler.throttle_info
  end

  def update
    settings_params.each do |key, value|
      SystemConfig.set(key, parse_value(value))
    end

    flash[:notice] = 'Tracking settings updated successfully'
    redirect_to dashboard_tracking_settings_path
  rescue StandardError => e
    flash[:error] = "Failed to update settings: #{e.message}"
    redirect_to dashboard_tracking_settings_path
  end

  def enable_warmup
    EmailThrottler.enable_warmup!
    flash[:notice] = 'Warmup mode enabled'
    redirect_to dashboard_tracking_settings_path
  end

  def disable_warmup
    EmailThrottler.disable_warmup!
    flash[:notice] = 'Warmup mode disabled'
    redirect_to dashboard_tracking_settings_path
  end

  def check_reputation
    @reputation = DomainReputationChecker.new.check_all
    render json: @reputation
  end

  private

  def settings_params
    params.require(:tracking_settings).permit(
      :enable_open_tracking,
      :enable_click_tracking,
      :tracking_domain,
      :use_utm_tracking,
      :max_tracked_links,
      :tracking_footer_enabled,
      :daily_send_limit
    )
  end

  def load_tracking_settings
    {
      enable_open_tracking: SystemConfig.get(:enable_open_tracking) || false,
      enable_click_tracking: SystemConfig.get(:enable_click_tracking) || true,
      tracking_domain: SystemConfig.get(:tracking_domain),
      use_utm_tracking: SystemConfig.get(:use_utm_tracking) || true,
      max_tracked_links: SystemConfig.get(:max_tracked_links) || 5,
      tracking_footer_enabled: SystemConfig.get(:tracking_footer_enabled) || true,
      daily_send_limit: SystemConfig.get(:daily_send_limit) || 500
    }
  end

  def parse_value(value)
    case value
    when 'true' then true
    when 'false' then false
    when /^\d+$/ then value.to_i
    else value
    end
  end
end
