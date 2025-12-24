class ReportToAmsJob < ApplicationJob
  queue_as :low

  def perform(external_message_id, event_type, error_message = nil)
    email_log = EmailLog.find_by_external_message_id(external_message_id)
    return unless email_log
    
    webhook_sender = WebhookSender.new(
      callback_url: ENV.fetch("AMS_CALLBACK_URL", ""),
      webhook_secret: ENV.fetch("WEBHOOK_SECRET"),
      server_id: ENV.fetch("DOMAIN", "send1.example.com")
    )
    
    data = {
      message_id: email_log.external_message_id,
      local_message_id: email_log.message_id,
      campaign_id: email_log.campaign_id,
      recipient: email_log.recipient_masked,
      status: event_type
    }
    
    data[:error] = error_message if error_message
    
    webhook_sender.send(
      event_type: event_type,
      data: data
    )
  rescue => e
    Rails.logger.error "ReportToAmsJob error: #{e.message}"
    # Don't fail the job, just log
  end
end





