# frozen_string_literal: true

class CreateSystemConfigs < ActiveRecord::Migration[7.1]
  def change
    create_table :system_configs do |t|
      # Server Configuration
      t.string :domain, null: false
      t.string :allowed_sender_domains
      t.string :cors_origins

      # AMS Integration
      t.string :ams_callback_url
      t.text :ams_api_key_encrypted  # Encrypted
      t.string :ams_api_url

      # Postal Configuration
      t.string :postal_api_url, default: 'http://postal:5000'
      t.text :postal_api_key_encrypted  # Encrypted
      t.text :postal_signing_key_encrypted  # Encrypted

      # Limits & Security
      t.integer :daily_limit, default: 50000
      t.integer :sidekiq_concurrency, default: 5
      t.text :webhook_secret_encrypted  # Encrypted

      # Metadata for tracking changes
      t.jsonb :changed_fields, default: {}
      t.boolean :restart_required, default: false
      t.string :restart_services, array: true, default: []

      t.timestamps
    end

    # Add index for singleton pattern
    add_index :system_configs, :id, unique: true
  end
end
