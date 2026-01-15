class CreateEmailClicks < ActiveRecord::Migration[7.0]
  def change
    create_table :email_clicks do |t|
      t.references :email_log, null: false, foreign_key: true
      t.string :campaign_id, null: false
      t.string :url, null: false, limit: 2048
      t.string :ip_address
      t.string :user_agent, limit: 1024
      t.string :token, null: false, index: { unique: true }
      t.datetime :clicked_at, null: false

      t.timestamps
    end

    add_index :email_clicks, [:campaign_id, :clicked_at]
    add_index :email_clicks, [:email_log_id, :url]
  end
end
