# frozen_string_literal: true

class AddBounceCategoryIndex < ActiveRecord::Migration[7.1]
  def change
    add_index :bounced_emails, :bounce_category, name: 'idx_bounced_emails_bounce_category'
  end
end


