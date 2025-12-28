class CreateDeliveryErrors < ActiveRecord::Migration[7.1]
  def change
    create_table :delivery_errors do |t|
      t.references :email_log, null: false, foreign_key: { on_delete: :cascade }
      t.string :campaign_id, limit: 64, null: false
      t.string :category, limit: 30, null: false
      t.string :smtp_code, limit: 10
      t.text :smtp_message
      t.string :recipient_domain, limit: 255
      t.timestamps
    end
    
    add_index :delivery_errors, [:campaign_id, :category, :created_at], name: 'idx_delivery_errors_campaign_category_created'
    add_index :delivery_errors, [:category, :created_at], name: 'idx_delivery_errors_category_created'
  end
end

