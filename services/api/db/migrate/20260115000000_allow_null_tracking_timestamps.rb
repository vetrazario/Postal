class AllowNullTrackingTimestamps < ActiveRecord::Migration[7.0]
  def up
    # Разрешить NULL для clicked_at (заполняется при первом клике)
    change_column_null :email_clicks, :clicked_at, true
    
    # Разрешить NULL для opened_at (заполняется при первом открытии)
    change_column_null :email_opens, :opened_at, true
  end

  def down
    # Если откатываем - сначала заполним NULL значения
    EmailClick.where(clicked_at: nil).update_all(clicked_at: Time.current)
    EmailOpen.where(opened_at: nil).update_all(opened_at: Time.current)
    
    change_column_null :email_clicks, :clicked_at, false
    change_column_null :email_opens, :opened_at, false
  end
end
