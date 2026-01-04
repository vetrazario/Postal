# frozen_string_literal: true

class SendSmtpEmailJob < ApplicationJob
  queue_as :default

  # Retry on transient failures (network issues, temporary Postal unavailability)
  retry_on StandardError, wait: :polynomially_longer, attempts: 5
  discard_on ActiveRecord::RecordNotFound # Don't retry if email_log was deleted

  # Process email received from SMTP Relay
  def perform(email_data)
    # Ensure hash with indifferent access
    email_data = email_data.with_indifferent_access if email_data.is_a?(Hash)

    email_log = EmailLog.find(email_data[:email_log_id])

    # Update status
    email_log.update!(status: 'processing')

    # Extract data (from server.js format)
    envelope = email_data[:envelope].with_indifferent_access
    message = email_data[:message].with_indifferent_access
    raw = email_data[:raw]

    # Build email payload for Postal
    # Use HTML if available, otherwise wrap text in HTML
    html_content = if message[:html].present? && message[:html] != false
                     message[:html]
                   else
                     "<pre>#{message[:text]}</pre>"
                   end

    postal_payload = {
      to: envelope[:to].is_a?(Array) ? envelope[:to].first : envelope[:to],
      from: envelope[:from],
      subject: message[:subject],
      html_body: html_content,
      headers: build_custom_headers(message),
      tag: 'smtp-relay'
    }

    # Send to Postal
    postal_client = PostalClient.new(
      api_url: ENV.fetch('POSTAL_API_URL', 'http://postal:5000'),
      api_key: ENV.fetch('POSTAL_API_KEY')
    )
    response = postal_client.send_message(**postal_payload)

    if response[:success]
      # Update email log
      email_log.update!(
        status: 'sent',
        postal_message_id: response[:message_id],
        sent_at: Time.current
      )

      Rails.logger.info "SMTP email sent successfully: #{email_log.message_id}"

      # Send webhook to AMS if configured
      send_webhook_to_ams(email_log, 'sent', response)
    else
      # Mark as failed
      email_log.update!(
        status: 'failed',
        status_details: { error: response[:error] }
      )

      Rails.logger.error "SMTP email failed: #{response[:error]}"

      # Send failure webhook
      send_webhook_to_ams(email_log, 'failed', response)
    end

  rescue => e
    Rails.logger.error "SendSmtpEmailJob error: #{e.message}"

    # Update email log with error (no backtrace for security)
    begin
      email_data = email_data.with_indifferent_access if email_data.is_a?(Hash)
      email_log = EmailLog.find(email_data[:email_log_id])
      email_log.update!(
        status: 'failed',
        status_details: { error: e.class.name, message: e.message.truncate(200) }
      )
    rescue => update_error
      Rails.logger.error "Failed to update email log: #{update_error.message}"
    end

    # Re-raise for retry logic
    raise e
  end

  private

  def build_custom_headers(message)
    custom_headers = {}

    # Add Reply-To if present in message headers
    if message[:headers].is_a?(Hash)
      reply_to = message[:headers]['reply-to'] || message[:headers]['Reply-To']
      custom_headers['Reply-To'] = reply_to if reply_to.present?
    end

    # NOTE: Do NOT pass X-Campaign-ID, X-Mailing-ID, X-Affiliate-ID or any AMS headers
    # to Postal - they are for internal tracking only and must not reach the recipient

    custom_headers
  end

  def format_attachments(attachments)
    return [] if attachments.blank?

    attachments.map do |att|
      {
        name: att['filename'] || 'attachment',
        content_type: att['content_type'] || 'application/octet-stream',
        data: att['data'] || att['content'] # base64 encoded
      }
    end
  end

  def send_webhook_to_ams(email_log, event_type, response_data)
    # Find active webhook endpoints
    WebhookEndpoint.active.for_event(event_type).each do |endpoint|
      webhook_data = {
        message_id: email_log.message_id,
        campaign_id: email_log.campaign_id,
        recipient: email_log.recipient_masked,
        status: event_type,
        timestamp: Time.current.iso8601,
        postal_message_id: email_log.postal_message_id,
        details: response_data
      }

      endpoint.send_webhook(event_type, webhook_data)
    end
  rescue => e
    Rails.logger.error "Webhook send error: #{e.message}"
    # Don't fail the job if webhook fails
  end
end
