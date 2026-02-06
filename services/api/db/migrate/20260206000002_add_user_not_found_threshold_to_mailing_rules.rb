# frozen_string_literal: true

class AddUserNotFoundThresholdToMailingRules < ActiveRecord::Migration[7.1]
  def change
    unless column_exists?(:mailing_rules, :max_user_not_found_errors)
      add_column :mailing_rules, :max_user_not_found_errors, :integer, default: 3
    end
  end
end
