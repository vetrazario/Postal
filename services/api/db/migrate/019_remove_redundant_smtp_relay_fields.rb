# frozen_string_literal: true

class RemoveRedundantSmtpRelayFields < ActiveRecord::Migration[7.0]
  def change
    # These fields are redundant because SmtpCredential model handles
    # SMTP authentication (username/password pairs for AMS connections)
    #
    # Keeping:
    # - smtp_relay_secret (for HMAC signing between SMTP Relay and API)
    # - smtp_relay_port (SMTP Relay server port)
    # - smtp_relay_auth_required (whether auth is required)
    # - smtp_relay_tls_enabled (whether TLS is enabled)

    safety_assured do
      remove_column :system_configs, :smtp_relay_username, :string, if_exists: true
      remove_column :system_configs, :smtp_relay_password_encrypted, :text, if_exists: true
    end
  end
end
