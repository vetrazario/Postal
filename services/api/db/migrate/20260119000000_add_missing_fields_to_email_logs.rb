# frozen_string_literal: true

class AddMissingFieldsToEmailLogs < ActiveRecord::Migration[7.1]
  def change
    # Add external_message_id field (used for tracking from external systems)
    add_column :email_logs, :external_message_id, :string, limit: 64, if_not_exists: true
    add_index :email_logs, :external_message_id, if_not_exists: true

    # Add sent_at timestamp
    add_column :email_logs, :sent_at, :timestamp, if_not_exists: true

    # Add delivered_at timestamp
    add_column :email_logs, :delivered_at, :timestamp, if_not_exists: true

    # Add status_details JSONB field
    add_column :email_logs, :status_details, :jsonb, if_not_exists: true

    # Ensure campaign_id and external_message_id can be null
    change_column_null :email_logs, :campaign_id, true rescue nil
    change_column_null :email_logs, :external_message_id, true rescue nil
  end
end
