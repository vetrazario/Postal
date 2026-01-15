class AddTrackingSettings < ActiveRecord::Migration[7.0]
  def change
    # Add tracking configuration columns to system_configs
    add_column :system_configs, :enable_open_tracking, :boolean, default: false
    add_column :system_configs, :enable_click_tracking, :boolean, default: true
    add_column :system_configs, :tracking_domain, :string
    add_column :system_configs, :use_utm_tracking, :boolean, default: true
    add_column :system_configs, :max_tracked_links, :integer, default: 5
    add_column :system_configs, :tracking_footer_enabled, :boolean, default: true
    add_column :system_configs, :daily_send_limit, :integer, default: 500
    add_column :system_configs, :warmup_mode, :boolean, default: false
  end
end
