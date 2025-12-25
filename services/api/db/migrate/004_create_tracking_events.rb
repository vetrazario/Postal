class CreateTrackingEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :tracking_events do |t|
      t.references :email_log, null: false, foreign_key: { on_delete: :cascade }
      t.string :event_type, null: false, limit: 20
      t.jsonb :event_data
      t.inet :ip_address
      t.text :user_agent

      t.timestamps
    end

    add_index :tracking_events, :event_type
    add_index :tracking_events, :created_at
    add_index :tracking_events, [:event_type, :created_at], name: "idx_tracking_type_created"
    
    add_check_constraint :tracking_events, "event_type IN ('open', 'click', 'bounce', 'complaint', 'delivered')", name: "tracking_events_type_check"
  end
end
