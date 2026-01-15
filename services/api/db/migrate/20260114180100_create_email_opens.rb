class CreateEmailOpens < ActiveRecord::Migration[7.0]
  def change
    create_table :email_opens do |t|
      t.references :email_log, null: false, foreign_key: true
      t.string :campaign_id, null: false
      t.string :ip_address
      t.string :user_agent, limit: 1024
      t.string :token, null: false, index: { unique: true }
      t.datetime :opened_at, null: false

      t.timestamps
    end

    add_index :email_opens, [:campaign_id, :opened_at]
    add_index :email_opens, :email_log_id
  end
end
