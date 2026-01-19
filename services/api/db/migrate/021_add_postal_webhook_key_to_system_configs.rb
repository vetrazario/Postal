# frozen_string_literal: true

class AddPostalWebhookKeyToSystemConfigs < ActiveRecord::Migration[7.0]
  def change
    # Postal webhook public key for verifying incoming webhooks
    add_column :system_configs, :postal_webhook_public_key_encrypted, :text

    # Sidekiq Web UI credentials
    add_column :system_configs, :sidekiq_web_username, :string
    add_column :system_configs, :sidekiq_web_password_encrypted, :text

    # Logging settings
    add_column :system_configs, :log_level, :string, default: 'info'
    add_column :system_configs, :sentry_dsn, :string

    # Let's Encrypt email
    add_column :system_configs, :letsencrypt_email, :string
  end
end
