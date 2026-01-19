# frozen_string_literal: true

class AddSmtpRelayToSystemConfigs < ActiveRecord::Migration[7.1]
  def change
    # SMTP Relay Authentication
    add_column :system_configs, :smtp_relay_username, :string
    add_column :system_configs, :smtp_relay_password_encrypted, :text  # Encrypted
    add_column :system_configs, :smtp_relay_secret_encrypted, :text    # Encrypted (HMAC key)

    # SMTP Relay Connection Settings
    add_column :system_configs, :smtp_relay_port, :integer, default: 2587
    add_column :system_configs, :smtp_relay_auth_required, :boolean, default: true
    add_column :system_configs, :smtp_relay_tls_enabled, :boolean, default: true
  end
end
