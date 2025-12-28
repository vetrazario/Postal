class CreateMailingRules < ActiveRecord::Migration[7.1]
  def change
    create_table :mailing_rules do |t|
      t.string :name, null: false, default: 'Default Rule'
      t.boolean :active, default: true
      
      # Thresholds (percentage or absolute)
      t.integer :max_bounce_rate, default: 10
      t.integer :max_rate_limit_errors, default: 5
      t.integer :max_spam_blocks, default: 3
      t.integer :check_window_minutes, default: 60
      
      # Actions
      t.boolean :auto_stop_mailing, default: true
      t.boolean :notify_email, default: false
      t.string :notification_email
      
      # AMS Integration
      t.string :ams_api_url
      t.text :ams_api_key_encrypted
      
      t.timestamps
    end
  end
end

