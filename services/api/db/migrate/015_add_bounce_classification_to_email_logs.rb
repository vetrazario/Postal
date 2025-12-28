class AddBounceClassificationToEmailLogs < ActiveRecord::Migration[7.1]
  def change
    add_column :email_logs, :bounce_category, :string, limit: 30
    add_column :email_logs, :smtp_code, :string, limit: 10
    add_column :email_logs, :smtp_message, :text
    
    add_index :email_logs, [:campaign_id, :bounce_category], 
               name: 'idx_email_logs_campaign_bounce_category',
               where: 'bounce_category IS NOT NULL'
  end
end

