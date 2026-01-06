# frozen_string_literal: true

class NotificationMailer < ApplicationMailer
  def threshold_alert(campaign_id:, violations:, rule:)
    @campaign_id = campaign_id
    @violations = violations
    @rule = rule
    
    mail(
      to: rule.notification_email,
      subject: "⚠️ Threshold Alert: Campaign #{campaign_id}",
      content_type: 'text/html'
    )
  end
end

