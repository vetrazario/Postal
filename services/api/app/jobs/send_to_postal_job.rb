class SendToPostalJob < ApplicationJob
  queue_as :default

  def perform(email_log_id, html_body)
    email_log = EmailLog.find_by(id: email_log_id)
    return unless email_log
    return if email_log.status.in?(%w[sent delivered])

    # Check if email is blocked (unsubscribed or bounced)
    if Unsubscribe.blocked?(email: email_log.recipient, campaign_id: email_log.campaign_id)
      email_log.update!(status: 'failed', status_details: { reason: 'unsubscribed' })
      Rails.logger.warn "Email #{email_log.recipient_masked} is unsubscribed, skipping send to Postal"
      return
    end

    if BouncedEmail.blocked?(email: email_log.recipient, campaign_id: email_log.campaign_id)
      email_log.update!(status: 'failed', status_details: { reason: 'bounced' })
      Rails.logger.warn "Email #{email_log.recipient_masked} is bounced, skipping send to Postal"
      return
    end

    result = postal_client.send_message(
      to: email_log.recipient,
      from: email_log.sender,
      subject: email_log.subject,
      html_body: html_body,
      headers: {},
      tag: email_log.campaign_id,
      campaign_id: email_log.campaign_id,
      track_clicks: false,
      track_opens: false
    )

    handle_result(email_log, result)
  rescue StandardError => e
    Rails.logger.error "SendToPostalJob error: #{e.message}"
    email_log&.update_status('failed', details: { error: e.message })
  end

  private

  def postal_client
    @postal_client ||= PostalClient.new(
      api_url: ENV.fetch('POSTAL_API_URL', 'http://postal:5000'),
      api_key: ENV.fetch('POSTAL_API_KEY')
    )
  end

  def handle_result(email_log, result)
    if result[:success]
      email_log.update!(postal_message_id: result[:message_id], status: 'sent', sent_at: Time.current)
      ReportToAmsJob.perform_later(email_log.external_message_id, 'sent')
    else
      email_log.update_status('failed', details: { error: result[:error] })
      ReportToAmsJob.perform_later(email_log.external_message_id, 'failed', result[:error])
    end
  end
end
