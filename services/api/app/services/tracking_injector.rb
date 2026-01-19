# frozen_string_literal: true

# TrackingInjector - wrapper around LinkTracker for backwards compatibility
# Injects tracking links and pixels into HTML emails
# Works with TrackingController which handles /go/:slug and /t/o/:token routes
class TrackingInjector
  # Main entry point - process HTML and inject all tracking
  # Uses LinkTracker internally for proper URL generation and DB record creation
  def self.inject_all(html:, recipient:, campaign_id:, message_id:, domain:)
    return html if html.blank?

    # Find email_log for this message
    email_log = EmailLog.find_by(external_message_id: message_id)

    unless email_log
      Rails.logger.warn "TrackingInjector: EmailLog not found for message_id=#{message_id}"
      return html
    end

    # Use LinkTracker which properly creates EmailClick/EmailOpen records
    # and generates correct /go/:slug and /t/o/:token URLs
    tracker = LinkTracker.new(
      email_log: email_log,
      domain: domain,
      track_clicks: SystemConfig.get(:enable_click_tracking) != false,
      track_opens: SystemConfig.get(:enable_open_tracking) != false
    )

    tracker.process_html(html)
  end

  # Legacy methods for backwards compatibility
  def self.inject_tracking_links(html:, recipient:, campaign_id:, message_id:, domain:)
    return html if html.blank?

    email_log = EmailLog.find_by(external_message_id: message_id)
    return html unless email_log

    tracker = LinkTracker.new(email_log: email_log, domain: domain)
    tracker.track_links(html)
  end

  def self.inject_tracking_pixel(html:, recipient:, campaign_id:, message_id:, domain:)
    return html if html.blank?

    email_log = EmailLog.find_by(external_message_id: message_id)
    return html unless email_log

    tracker = LinkTracker.new(email_log: email_log, domain: domain)
    tracker.add_tracking_pixel(html)
  end
end
