# frozen_string_literal: true

class AddPerformanceIndexes < ActiveRecord::Migration[7.1]
  def change
    # Индексы для быстрого поиска tracking событий
    add_index :tracking_events, [:email_log_id, :event_type, :created_at], name: 'idx_tracking_events_lookup'
    
    # Индексы для статистики по кампаниям
    add_index :email_opens, :campaign_id, name: 'idx_email_opens_campaign'
    add_index :email_clicks, :campaign_id, name: 'idx_email_clicks_campaign'
    
    # Индексы для ошибок доставки (через email_log_id для связи с campaign_id)
    add_index :delivery_errors, [:email_log_id, :category, :created_at], name: 'idx_delivery_errors_lookup'
  end
end
