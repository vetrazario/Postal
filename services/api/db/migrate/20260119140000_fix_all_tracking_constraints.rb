class FixAllTrackingConstraints < ActiveRecord::Migration[7.1]
  def up
    # 1. Fix email_clicks - make email_log_id nullable
    if column_exists?(:email_clicks, :email_log_id)
      change_column_null :email_clicks, :email_log_id, true
    end

    # Ensure campaign_id has default
    if column_exists?(:email_clicks, :campaign_id)
      change_column_default :email_clicks, :campaign_id, 'unknown'
      execute "UPDATE email_clicks SET campaign_id = 'unknown' WHERE campaign_id IS NULL"
    end

    # 2. Fix email_opens - make email_log_id nullable
    if column_exists?(:email_opens, :email_log_id)
      change_column_null :email_opens, :email_log_id, true
    end

    # Ensure campaign_id has default
    if column_exists?(:email_opens, :campaign_id)
      change_column_default :email_opens, :campaign_id, 'unknown'
      execute "UPDATE email_opens SET campaign_id = 'unknown' WHERE campaign_id IS NULL"
    end

    # 3. Fix delivery_errors - make email_log_id nullable
    if column_exists?(:delivery_errors, :email_log_id)
      change_column_null :delivery_errors, :email_log_id, true
    end

    # Ensure campaign_id column exists and has default
    unless column_exists?(:delivery_errors, :campaign_id)
      add_column :delivery_errors, :campaign_id, :string, default: 'unknown'
    else
      change_column_default :delivery_errors, :campaign_id, 'unknown'
      execute "UPDATE delivery_errors SET campaign_id = 'unknown' WHERE campaign_id IS NULL"
    end

    # 4. Fix tracking_events - make email_log_id nullable if exists
    if table_exists?(:tracking_events) && column_exists?(:tracking_events, :email_log_id)
      change_column_null :tracking_events, :email_log_id, true
    end

    # 5. Remove foreign key constraints that might cause issues
    if foreign_key_exists?(:email_clicks, :email_logs)
      remove_foreign_key :email_clicks, :email_logs
    end

    if foreign_key_exists?(:email_opens, :email_logs)
      remove_foreign_key :email_opens, :email_logs
    end

    if foreign_key_exists?(:delivery_errors, :email_logs)
      remove_foreign_key :delivery_errors, :email_logs
    end

    if table_exists?(:tracking_events) && foreign_key_exists?(:tracking_events, :email_logs)
      remove_foreign_key :tracking_events, :email_logs
    end

    # 6. Fix unsubscribes table
    if table_exists?(:unsubscribes)
      if column_exists?(:unsubscribes, :email_log_id)
        change_column_null :unsubscribes, :email_log_id, true
      end

      if foreign_key_exists?(:unsubscribes, :email_logs)
        remove_foreign_key :unsubscribes, :email_logs
      end
    end

    # 7. Fix bounced_emails table
    if table_exists?(:bounced_emails)
      if column_exists?(:bounced_emails, :email_log_id)
        change_column_null :bounced_emails, :email_log_id, true
      end

      if foreign_key_exists?(:bounced_emails, :email_logs)
        remove_foreign_key :bounced_emails, :email_logs
      end
    end
  end

  def down
    # No rollback
  end
end
