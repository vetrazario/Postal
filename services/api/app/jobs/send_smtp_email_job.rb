# frozen_string_literal: true

class SendSmtpEmailJob < ApplicationJob
  queue_as :mailers

  # Process email received from SMTP Relay
  def perform(email_data)
    email_log = EmailLog.find(email_data['email_log_id'])

    # Update status
    email_log.update!(status: 'processing')

    # Extract data
    envelope = email_data['envelope'].with_indifferent_access
    headers = email_data['headers'].with_indifferent_access
    body = email_data['body'].with_indifferent_access
    attachments = email_data['attachments'] || []
    tracking = email_data['tracking'].with_indifferent_access

    # Build email payload for Postal
    postal_payload = {
      to: Array(envelope[:to]),
      from: headers[:from],
      subject: headers[:subject],
      plain_body: body[:plain],
      html_body: body[:html],
      headers: build_custom_headers(headers, tracking),
      attachments: format_attachments(attachments),
      tag: tracking[:campaign_id] || 'smtp'
    }

    # Send to Postal
    postal_client = PostalClient.new(
      api_url: ENV.fetch('POSTAL_API_URL', 'http://postal:5000'),
      api_key: ENV.fetch('POSTAL_API_KEY')
    )
    response = postal_client.send_message(postal_payload)

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
    Rails.logger.error e.backtrace.join("\n")

    # Update email log with error
    email_log = EmailLog.find(email_data['email_log_id'])
    email_log.update!(
      status: 'failed',
      status_details: { error: e.message, backtrace: e.backtrace.first(5) }
    )

    # Retry job
    raise e
  end

  private

  def build_custom_headers(headers, tracking)
    custom_headers = {}

    # Add Reply-To if present
    custom_headers['Reply-To'] = headers[:reply_to] if headers[:reply_to].present?

    # Add tracking metadata as custom headers
    custom_headers['X-Campaign-ID'] = tracking[:campaign_id] if tracking[:campaign_id]
    custom_headers['X-Affiliate-ID'] = tracking[:affiliate_id] if tracking[:affiliate_id]

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
