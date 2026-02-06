# frozen_string_literal: true

class AddBounceFieldsToEmailLogs < ActiveRecord::Migration[7.1]
  def change
    unless column_exists?(:email_logs, :bounce_category)
      add_column :email_logs, :bounce_category, :string, limit: 30
    end

    unless column_exists?(:email_logs, :smtp_code)
      add_column :email_logs, :smtp_code, :string, limit: 10
    end

    unless column_exists?(:email_logs, :smtp_message)
      add_column :email_logs, :smtp_message, :text
    end

    unless index_exists?(:email_logs, [:campaign_id, :bounce_category], name: 'idx_email_logs_campaign_bounce_category')
      add_index :email_logs, [:campaign_id, :bounce_category],
                name: 'idx_email_logs_campaign_bounce_category',
                where: 'bounce_category IS NOT NULL'
    end
  end
end
