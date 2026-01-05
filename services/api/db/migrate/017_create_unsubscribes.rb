# frozen_string_literal: true

class CreateUnsubscribes < ActiveRecord::Migration[7.1]
  def change
    create_table :unsubscribes do |t|
      t.string :email, null: false, limit: 255
      t.string :campaign_id, limit: 64  # null = глобальный unsubscribe
      t.string :reason, default: 'user_request', limit: 50
      t.inet :ip_address
      t.text :user_agent
      t.datetime :unsubscribed_at, null: false

      t.timestamps
    end

    add_index :unsubscribes, [:email, :campaign_id], unique: true, name: 'idx_unsubscribes_email_campaign'
    add_index :unsubscribes, :email, name: 'idx_unsubscribes_email'
    add_index :unsubscribes, :campaign_id, name: 'idx_unsubscribes_campaign'
    add_index :unsubscribes, :unsubscribed_at, name: 'idx_unsubscribes_unsubscribed_at'
  end
end

