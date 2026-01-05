# frozen_string_literal: true

class CreateBouncedEmails < ActiveRecord::Migration[7.1]
  def change
    create_table :bounced_emails do |t|
      t.string :email, null: false, limit: 255
      t.string :bounce_type, null: false, limit: 10  # 'hard' или 'soft'
      t.string :bounce_category, limit: 30  # user_not_found, spam_block, etc
      t.string :smtp_code, limit: 10
      t.text :smtp_message
      t.string :campaign_id, limit: 64  # null = глобальный блок
      t.integer :bounce_count, default: 1, null: false
      t.datetime :first_bounced_at, null: false
      t.datetime :last_bounced_at, null: false

      t.timestamps
    end

    add_index :bounced_emails, [:email, :campaign_id], unique: true, name: 'idx_bounced_emails_email_campaign'
    add_index :bounced_emails, :email, name: 'idx_bounced_emails_email'
    add_index :bounced_emails, :bounce_type, name: 'idx_bounced_emails_bounce_type'
    add_index :bounced_emails, :campaign_id, name: 'idx_bounced_emails_campaign'
    add_index :bounced_emails, :last_bounced_at, name: 'idx_bounced_emails_last_bounced_at'
    
    add_check_constraint :bounced_emails, "bounce_type IN ('hard', 'soft')", name: 'bounced_emails_bounce_type_check'
  end
end

