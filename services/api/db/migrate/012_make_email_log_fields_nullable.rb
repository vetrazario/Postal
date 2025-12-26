class MakeEmailLogFieldsNullable < ActiveRecord::Migration[7.1]
  def change
    change_column_null :email_logs, :external_message_id, true
    change_column_null :email_logs, :campaign_id, true
  end
end
