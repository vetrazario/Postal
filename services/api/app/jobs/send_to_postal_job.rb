class SendToPostalJob < ApplicationJob
  queue_as :default

  def perform(email_log_id, html_body)
    email_log = EmailLog.find_by(id: email_log_id)
    return unless email_log

    result = postal_client.send_message(
      to: email_log.recipient,
      from: email_log.sender,
      subject: email_log.subject,
      html_body: html_body,
      headers: {
        'X-Campaign-ID' => email_log.campaign_id,
        'X-Message-ID' => email_log.external_message_id
      },
      tag: email_log.campaign_id
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
