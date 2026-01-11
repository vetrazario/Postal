# frozen_string_literal: true

class MonitorBounceCategoriesJob < ApplicationJob
  queue_as :low

  CATEGORY_THRESHOLDS = {
    user_not_found: 0.1,   # 10% баунсов
    spam_block: 0.05,      # 5% баунсов
    mailbox_full: 0.03,    # 3% баунсов
    authentication: 0.02    # 2% баунсов
  }.freeze

  def perform(campaign_id)
    return unless campaign_id.present?

    # Получить статистику bounce за последние 24 часа
    bounces = BouncedEmail.where(campaign_id: campaign_id)
                         .where('last_bounced_at >= ?', 24.hours.ago)
    
    stats = calculate_bounce_stats(bounces)
    
    # Проверить пороги
    alerts = []
    
    CATEGORY_THRESHOLDS.each do |category, threshold|
      category_key = category.to_s
      if stats[category_key] && stats[category_key][:rate] >= threshold
        alerts << {
          category: category_key,
          threshold: threshold,
          actual_rate: stats[category_key][:rate],
          count: stats[category_key][:count]
        }
      end
    end
    
    # Отправить оповещения, если есть алерты
    if alerts.any?
      send_bounce_alerts(campaign_id, alerts)
    end
    
    Rails.logger.info "MonitorBounceCategoriesJob: Campaign #{campaign_id} - #{alerts.length} alerts"
  rescue StandardError => e
    Rails.logger.error "MonitorBounceCategoriesJob error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end

  private

  def calculate_bounce_stats(bounces)
    total = bounces.count
    return {} if total == 0

    stats = {}
    ErrorClassifier::ERROR_PATTERNS.keys.each do |category|
      category_key = category.to_s
      category_bounces = bounces.where(bounce_category: category_key)
      count = category_bounces.count
      stats[category_key] = {
        count: count,
        rate: (count.to_f / total).round(4)  # Доля от 0 до 1
      }
    end

    stats
  end

  def send_bounce_alerts(campaign_id, alerts)
    rule = MailingRule.instance
    
    # Отправить email
    if rule&.notify_email?
      begin
        NotificationMailer.bounce_category_alert(
          campaign_id: campaign_id,
          alerts: alerts,
          rule: rule
        ).deliver_later
        
        Rails.logger.info "Bounce category alert email sent to #{rule.notification_email} for campaign #{campaign_id}"
      rescue StandardError => e
        Rails.logger.error "Failed to send bounce category alert email: #{e.message}"
      end
    end

    # Отправить в AMS если настроено
    if rule&.ams_api_url.present? && rule&.ams_api_key.present?
      begin
        client = AmsClient.new(
          api_url: rule.ams_api_url,
          api_key: rule.ams_api_key
        )
        
        # Используем существующий метод send_threshold_alert
        client.send_threshold_alert(
          campaign_id: campaign_id,
          violations: alerts.map { |a| 
            {
              type: :bounce_category,
              message: "Bounce category #{a[:category]} exceeded threshold: #{(a[:actual_rate] * 100).round(2)}% (threshold: #{(a[:threshold] * 100).round(2)}%)",
              value: (a[:actual_rate] * 100).round(2),
              threshold: (a[:threshold] * 100).round(2)
            }
          }
        )
        
        Rails.logger.info "Bounce category alert sent to AMS for campaign #{campaign_id}"
      rescue StandardError => e
        Rails.logger.error "Failed to send bounce category alert to AMS: #{e.message}"
      end
    end
  end
end

