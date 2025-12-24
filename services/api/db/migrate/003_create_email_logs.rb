class CreateEmailLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :email_logs do |t|
      t.string :message_id, null: false, limit: 64
      t.string :external_message_id, null: false, limit: 64
      t.string :campaign_id, null: false, limit: 64
      t.references :template, foreign_key: { to_table: :email_templates }, null: true
      t.string :recipient, null: false, limit: 255
      t.string :recipient_masked, null: false, limit: 255
      t.string :sender, null: false, limit: 255
      t.string :subject, null: false, limit: 500
      t.string :postal_message_id, limit: 255
      t.string :status, null: false, default: 'queued', limit: 20
      t.jsonb :status_details
      t.timestamp :sent_at
      t.timestamp :delivered_at

      t.timestamps
    end

    add_index :email_logs, :message_id, unique: true
    add_index :email_logs, :external_message_id
    add_index :email_logs, :campaign_id
    add_index :email_logs, :status
    add_index :email_logs, :created_at
    add_index :email_logs, :recipient
    add_index :email_logs, [:campaign_id, :status], name: "idx_email_logs_campaign_status"
    add_index :email_logs, :created_at, where: "status IN ('queued', 'processing', 'sent')", name: "idx_email_logs_pending"
    
    add_check_constraint :email_logs, "status IN ('queued', 'processing', 'sent', 'delivered', 'bounced', 'failed', 'complained')", name: "email_logs_status_check"
  end
end





