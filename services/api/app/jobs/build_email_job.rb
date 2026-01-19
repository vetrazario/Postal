# frozen_string_literal: true

class BuildEmailJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(email_log_id)
    email_log = EmailLog.find_by(id: email_log_id)
    return unless email_log
    return if email_log.status.in?(%w[sent delivered])

    # Check if email is blocked (unsubscribed or bounced)
    block_result = EmailBlocker.blocked?(email: email_log.recipient, campaign_id: email_log.campaign_id)
    if block_result[:blocked]
      email_log.update!(status: 'failed', status_details: { reason: block_result[:reason] })
      Rails.logger.warn "Email #{email_log.recipient_masked} is #{block_result[:reason]}, skipping build"
      return
    end

    email_log.update!(status: 'processing')

    html_body = render_html(email_log)
    html_body = inject_tracking(html_body, email_log)

    SendToPostalJob.perform_later(email_log.id, html_body)
  end

  private

  def render_html(email_log)
    template = email_log.template
    variables = email_log.status_details&.dig('variables') || {}

    return template.render(variables) if template

    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><meta charset="utf-8"></head>
      <body><p>#{variables['body'] || 'Email content'}</p></body>
      </html>
    HTML
  end

  def inject_tracking(html, email_log)
    TrackingInjector.inject_all(
      html: html,
      recipient: email_log.recipient,
      campaign_id: email_log.campaign_id,
      message_id: email_log.external_message_id,
      domain: SystemConfig.get(:domain) || 'localhost'
    )
  end
end
