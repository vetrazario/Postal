# frozen_string_literal: true

class CreateSmtpCredentials < ActiveRecord::Migration[7.1]
  def change
    create_table :smtp_credentials do |t|
      t.string :username, null: false
      t.string :password_hash, null: false
      t.string :description
      t.boolean :active, default: true, null: false
      t.integer :rate_limit, default: 100, null: false, comment: 'Emails per hour'
      t.datetime :last_used_at

      t.timestamps
    end

    add_index :smtp_credentials, :username, unique: true
    add_index :smtp_credentials, :active
    add_index :smtp_credentials, :last_used_at
  end
end
