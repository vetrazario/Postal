class CreateDeliveryErrors < ActiveRecord::Migration[7.0]
  def change
    create_table :delivery_errors do |t|
      t.references :email_log, null: false, foreign_key: true
      t.string :campaign_id, null: false, limit: 64
      t.string :category, null: false, limit: 50
      t.text :error_message
      t.string :recipient, limit: 255
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :delivery_errors, :campaign_id
    add_index :delivery_errors, :category
    add_index :delivery_errors, :created_at
    add_index :delivery_errors, [:campaign_id, :category]
  end
end
