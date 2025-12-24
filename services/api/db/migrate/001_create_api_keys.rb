class CreateApiKeys < ActiveRecord::Migration[7.1]
  def change
    create_table :api_keys do |t|
      t.string :key_hash, null: false, limit: 64
      t.string :name, null: false
      t.jsonb :permissions, null: false, default: { send: true, batch: true }
      t.integer :rate_limit, null: false, default: 100
      t.integer :daily_limit, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamp :last_used_at

      t.timestamps
    end

    add_index :api_keys, :key_hash, unique: true
    add_index :api_keys, :key_hash, where: "active = true", name: "idx_api_keys_active"
    
    add_check_constraint :api_keys, "LENGTH(key_hash) = 64", name: "api_keys_key_hash_length"
  end
end





