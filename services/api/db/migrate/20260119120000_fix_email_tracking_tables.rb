class FixEmailTrackingTables < ActiveRecord::Migration[7.1]
  def up
    # Fix email_clicks table
    unless column_exists?(:email_clicks, :campaign_id)
      add_column :email_clicks, :campaign_id, :string
      # Заполняем campaign_id из связанного email_log
      execute <<-SQL
        UPDATE email_clicks
        SET campaign_id = COALESCE(
          (SELECT campaign_id FROM email_logs WHERE email_logs.id = email_clicks.email_log_id),
          'unknown'
        )
      SQL
      change_column_null :email_clicks, :campaign_id, false
      add_index :email_clicks, [:campaign_id, :clicked_at], if_not_exists: true
    end

    unless column_exists?(:email_clicks, :user_agent)
      add_column :email_clicks, :user_agent, :string, limit: 1024
    end

    # Fix email_opens table
    unless column_exists?(:email_opens, :campaign_id)
      add_column :email_opens, :campaign_id, :string
      # Заполняем campaign_id из связанного email_log
      execute <<-SQL
        UPDATE email_opens
        SET campaign_id = COALESCE(
          (SELECT campaign_id FROM email_logs WHERE email_logs.id = email_opens.email_log_id),
          'unknown'
        )
      SQL
      change_column_null :email_opens, :campaign_id, false
      add_index :email_opens, [:campaign_id, :opened_at], if_not_exists: true
    end

    unless column_exists?(:email_opens, :user_agent)
      add_column :email_opens, :user_agent, :string, limit: 1024
    end

    # Fix bounced_emails table - ensure email column exists
    unless column_exists?(:bounced_emails, :email)
      add_column :bounced_emails, :email, :string
      add_index :bounced_emails, :email, if_not_exists: true
      add_index :bounced_emails, [:email, :campaign_id], unique: true, if_not_exists: true
    end

    unless column_exists?(:bounced_emails, :campaign_id)
      add_column :bounced_emails, :campaign_id, :string
    end

    # Remove email_log_id constraint from bounced_emails if exists
    if column_exists?(:bounced_emails, :email_log_id)
      change_column_null :bounced_emails, :email_log_id, true
    end

    # Fix unsubscribes table - ensure email column exists
    unless column_exists?(:unsubscribes, :email)
      add_column :unsubscribes, :email, :string
      add_index :unsubscribes, :email, if_not_exists: true
    end

    unless column_exists?(:unsubscribes, :campaign_id)
      add_column :unsubscribes, :campaign_id, :string
      add_index :unsubscribes, [:email, :campaign_id], unique: true, if_not_exists: true
    end

    # Remove email_log_id constraint from unsubscribes if exists
    if column_exists?(:unsubscribes, :email_log_id)
      change_column_null :unsubscribes, :email_log_id, true
    end

    # Fix delivery_errors table - ensure category column exists
    unless column_exists?(:delivery_errors, :category)
      if column_exists?(:delivery_errors, :status_code)
        rename_column :delivery_errors, :status_code, :category
      else
        add_column :delivery_errors, :category, :string, null: false, default: 'unknown'
      end
    end

    # Fix mailing_rules table
    unless column_exists?(:mailing_rules, :ams_api_url)
      add_column :mailing_rules, :ams_api_url, :string
    end

    unless column_exists?(:mailing_rules, :ams_api_key_encrypted)
      add_column :mailing_rules, :ams_api_key_encrypted, :text
    end

    unless column_exists?(:mailing_rules, :auto_stop_mailing)
      add_column :mailing_rules, :auto_stop_mailing, :boolean, default: true
    end

    unless column_exists?(:mailing_rules, :notification_email)
      add_column :mailing_rules, :notification_email, :string
    end

    unless column_exists?(:mailing_rules, :max_bounce_rate)
      add_column :mailing_rules, :max_bounce_rate, :integer, default: 10
    end

    unless column_exists?(:mailing_rules, :max_rate_limit_errors)
      add_column :mailing_rules, :max_rate_limit_errors, :integer, default: 5
    end

    unless column_exists?(:mailing_rules, :max_spam_blocks)
      add_column :mailing_rules, :max_spam_blocks, :integer, default: 3
    end

    unless column_exists?(:mailing_rules, :check_window_minutes)
      add_column :mailing_rules, :check_window_minutes, :integer, default: 60
    end
  end

  def down
    # No rollback - these are fixes
  end
end
