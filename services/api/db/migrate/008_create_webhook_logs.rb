# frozen_string_literal: true

class CreateWebhookLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :webhook_logs do |t|
      t.references :webhook_endpoint, null: false, foreign_key: true
      t.string :event_type, null: false
      t.string :message_id
      t.integer :response_code
      t.text :response_body
      t.boolean :success, default: false, null: false
      t.datetime :delivered_at
      t.float :duration_ms, comment: 'Request duration in milliseconds'
      t.text :error_message

      t.timestamps
    end

    add_index :webhook_logs, :message_id
    add_index :webhook_logs, :event_type
    add_index :webhook_logs, :success
    add_index :webhook_logs, :created_at
    add_index :webhook_logs, [:webhook_endpoint_id, :created_at]
  end
end
