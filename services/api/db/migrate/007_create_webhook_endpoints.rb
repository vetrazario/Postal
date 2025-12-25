# frozen_string_literal: true

class CreateWebhookEndpoints < ActiveRecord::Migration[7.1]
  def change
    create_table :webhook_endpoints do |t|
      t.string :url, null: false
      t.string :secret_key
      t.boolean :active, default: true, null: false
      t.json :events, default: ['delivered', 'opened', 'clicked', 'bounced', 'failed', 'complained']
      t.integer :retry_count, default: 3, null: false
      t.integer :timeout, default: 30, null: false, comment: 'Timeout in seconds'
      t.integer :successful_deliveries, default: 0, null: false
      t.integer :failed_deliveries, default: 0, null: false
      t.datetime :last_success_at
      t.datetime :last_failure_at

      t.timestamps
    end

    add_index :webhook_endpoints, :active
    add_index :webhook_endpoints, :url
  end
end
