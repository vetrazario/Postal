# frozen_string_literal: true

class CheckMailingThresholdsJob < ApplicationJob
  queue_as :critical

  def perform(campaign_id)
    return unless campaign_id.present?

    rule = MailingRule.instance
    return unless rule&.active?

    violations = rule.thresholds_exceeded?(campaign_id)
    
    # Проверить критические bounce категории за последние 5 минут
    critical_bounce_exists = DeliveryError.where(campaign_id: campaign_id)
                                         .where(category: ErrorClassifier::STOP_MAILING_CATEGORIES)
                                         .where('created_at > ?', 5.minutes.ago)
                                         .exists?
    
    if critical_bounce_exists
      violations ||= []
      violations << {
        type: :critical_bounce,
        message: 'Critical bounce detected (rate_limit, spam_block, mailbox_full, etc)',
        value: 1,
        threshold: 0
      }
    end
    
    return unless violations

    Rails.logger.warn "Mailing #{campaign_id}: Thresholds exceeded: #{violations.map { |v| v[:message] }.join(', ')}"

    if rule.auto_stop_mailing? && rule.ams_api_url.present? && rule.ams_api_key.present?
      stop_mailing_via_ams(rule, campaign_id, violations)
    end

    send_notifications(rule, campaign_id, violations) if rule.notify_email?
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

    # Отправить email уведомление
    begin
      NotificationMailer.threshold_alert(
        campaign_id: campaign_id,
        violations: violations,
        rule: rule
      ).deliver_later
      
      Rails.logger.info "Threshold alert email sent to #{rule.notification_email} for campaign #{campaign_id}"
    rescue => e
      Rails.logger.error "Failed to send threshold alert email: #{e.message}"
    end

    # Отправить уведомление в AMS если настроено
    if rule.ams_api_url.present? && rule.ams_api_key.present?
      begin
        client = AmsClient.new(
          api_url: rule.ams_api_url,
          api_key: rule.ams_api_key
        )
        
        client.send_threshold_alert(
          campaign_id: campaign_id,
          violations: violations
        )
        
        Rails.logger.info "Threshold alert sent to AMS for campaign #{campaign_id}"
      rescue => e
        Rails.logger.error "Failed to send threshold alert to AMS: #{e.message}"
      end
    end
  end
end

