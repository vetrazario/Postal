# frozen_string_literal: true

class UpdateCampaignStatsJob < ApplicationJob
  queue_as :low

  def perform(campaign_id, event_type, email_log_id = nil)
    return unless campaign_id.present?
    
    stats = CampaignStats.find_or_initialize_for(campaign_id)
    
    case event_type
    when 'open'
      stats.increment_opened
      
      # Обновить уникальные открытия (пересчитываем всегда для точности)
      unique_opens = TrackingEvent
        .joins(:email_log)
        .where(email_logs: { campaign_id: campaign_id }, event_type: 'open')
        .distinct
        .count(:email_log_id)
      
      stats.update_column(:unique_opened, unique_opens)
      
    when 'click'
      stats.increment_clicked
      
      # Обновить уникальные клики (пересчитываем всегда для точности)
      unique_clicks = TrackingEvent
        .joins(:email_log)
        .where(email_logs: { campaign_id: campaign_id }, event_type: 'click')
        .distinct
        .count(:email_log_id)
      
      stats.update_column(:unique_clicked, unique_clicks)
      
    when 'unsubscribe'
      # Можно добавить счетчик для unsubscribes если нужно
      Rails.logger.info "Unsubscribe event for campaign #{campaign_id}"
    end
    
    Rails.logger.info "Updated stats for campaign #{campaign_id}: #{event_type}"
  rescue => e
    Rails.logger.error "UpdateCampaignStatsJob error: #{e.message}\n#{e.backtrace.join("\n")}"
  end
end

