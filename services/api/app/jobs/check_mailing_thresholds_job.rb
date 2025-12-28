# frozen_string_literal: true

class CheckMailingThresholdsJob < ApplicationJob
  queue_as :critical

  def perform(campaign_id)
    return unless campaign_id.present?

    rule = MailingRule.instance
    return unless rule&.active?

    violations = rule.thresholds_exceeded?(campaign_id)
    return unless violations

    Rails.logger.warn "Mailing #{campaign_id}: Thresholds exceeded: #{violations.map { |v| v[:message] }.join(', ')}"

    if rule.auto_stop_mailing? && rule.ams_api_url.present? && rule.ams_api_key.present?
      stop_mailing_via_ams(rule, campaign_id, violations)
    end

    send_notifications(rule, campaign_id, violations) if rule.notify_email? && rule.notification_email.present?
  rescue StandardError => e
    Rails.logger.error "CheckMailingThresholdsJob error for campaign #{campaign_id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end

  private

  def stop_mailing_via_ams(rule, campaign_id, violations)
    client = AmsClient.new(
      api_url: rule.ams_api_url,
      api_key: rule.ams_api_key
    )

    # Получаем список рассылок
    result = client.get_mailings
    return unless result[:success]

    mailings = result[:result] || []
    mailing = find_mailing_by_campaign_id(mailings, campaign_id)

    if mailing && mailing['state'] == 'running'
      stop_result = client.stop_mailing(mailing['id'])
      
      if stop_result[:success]
        Rails.logger.info "Mailing #{campaign_id} (AMS ID: #{mailing['id']}) stopped successfully"
        Rails.logger.info "Reasons: #{violations.map { |v| v[:message] }.join('; ')}"
      else
        Rails.logger.error "Failed to stop mailing #{campaign_id}: #{stop_result[:error]}"
      end
    else
      Rails.logger.warn "Mailing #{campaign_id} not found or not running in AMS"
    end
  rescue AmsClient::ConnectionError, AmsClient::AuthenticationError, AmsClient::ApiError => e
    Rails.logger.error "AMS API error when stopping mailing #{campaign_id}: #{e.message}"
  end

  def find_mailing_by_campaign_id(mailings, campaign_id)
    # Пытаемся найти по ID (если campaign_id это числовой ID AMS)
    mailing = mailings.find { |m| m['id'].to_s == campaign_id.to_s }
    return mailing if mailing

    # Если не нашли, ищем по имени (может содержать campaign_id)
    mailings.find { |m| m['name']&.include?(campaign_id.to_s) }
  end

  def send_notifications(rule, campaign_id, violations)
    return unless rule.notification_email.present?

    subject = "Mailing #{campaign_id} stopped due to threshold violations"
    message = violations.map { |v| "- #{v[:message]}" }.join("\n")
    
    # Здесь можно использовать ActionMailer или другой способ отправки
    Rails.logger.info "Would send notification to #{rule.notification_email}: #{subject}\n#{message}"
    
    # TODO: Реализовать отправку email через ActionMailer
    # NotificationMailer.mailing_stopped(
    #   to: rule.notification_email,
    #   campaign_id: campaign_id,
    #   violations: violations
    # ).deliver_later
  end
end

