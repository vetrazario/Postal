# frozen_string_literal: true

class ReportToAmsJob < ApplicationJob
  queue_as :low

  def perform(external_message_id, event_type, error_message = nil, additional_data = nil)
    return if external_message_id.blank?
    
    email_log = EmailLog.find_by(external_message_id: external_message_id)
    
    # Для некоторых событий (например, unsubscribe) email_log может быть не найден
    # В этом случае используем данные из additional_data
    if email_log
      webhook_data = {
        message_id: email_log.external_message_id,
        local_message_id: email_log.message_id,
        campaign_id: email_log.campaign_id,
        recipient: email_log.recipient_masked,
        status: event_type,
        timestamp: Time.current.iso8601,
        postal_message_id: email_log.postal_message_id
      }
    else
      # Используем данные из additional_data если email_log не найден
      webhook_data = (additional_data || {}).merge(
        message_id: external_message_id,
        status: event_type,
        timestamp: Time.current.iso8601
      )
    end
    
    webhook_data[:error] = error_message if error_message.present?
    webhook_data.merge!(additional_data) if additional_data.is_a?(Hash)
    
    # Отправляем через все активные webhooks для данного события
    WebhookEndpoint.active.for_event(event_type).each do |endpoint|
      endpoint.send_webhook(event_type, webhook_data)
    rescue StandardError => e
      Rails.logger.error "ReportToAmsJob: Failed to send webhook to #{endpoint.url}: #{e.message}"
    end
  rescue StandardError => e
    Rails.logger.error "ReportToAmsJob error: #{e.message}"
    # Don't fail the job, just log
  end
end





