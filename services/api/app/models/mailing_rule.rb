# frozen_string_literal: true

class MailingRule < ApplicationRecord
  encrypts :ams_api_key_encrypted, deterministic: false

  validates :name, presence: true
  validates :max_bounce_rate, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :max_rate_limit_errors, numericality: { greater_than_or_equal_to: 0 }
  validates :max_spam_blocks, numericality: { greater_than_or_equal_to: 0 }
  validates :max_user_not_found_errors, numericality: { greater_than_or_equal_to: 0 }
  validates :check_window_minutes, numericality: { greater_than: 0 }
  validates :notification_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :ams_api_url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }, allow_blank: true

  # Singleton pattern - одна активная запись
  def self.instance
    first_or_create!(name: 'Default Rule')
  end

  def ams_api_key
    return nil if ams_api_key_encrypted.blank?
    ams_api_key_encrypted
  end

  def ams_api_key=(value)
    self.ams_api_key_encrypted = value.presence
  end

  def thresholds_exceeded?(campaign_id)
    return false unless active?
    return false unless auto_stop_mailing?

    window = check_window_minutes
    errors = DeliveryError.by_campaign(campaign_id).in_window(window)

    # Подсчёт статистики
    # Считаем все письма в окне (включая queued/processing для корректного расчета bounce_rate)
    total_sent = EmailLog.where(campaign_id: campaign_id)
                         .where('created_at > ?', window.minutes.ago)
                         .count

    total_bounced = errors.count
    bounce_rate = total_sent > 0 ? (total_bounced.to_f / total_sent * 100) : 0

    rate_limit_count = errors.by_category('rate_limit').count
    spam_block_count = errors.by_category('spam_block').count
    user_not_found_count = errors.by_category('user_not_found').count

    violations = []

    if bounce_rate > max_bounce_rate
      violations << {
        type: :bounce_rate,
        value: bounce_rate.round(2),
        threshold: max_bounce_rate,
        message: "Bounce rate #{bounce_rate.round(2)}% exceeds threshold of #{max_bounce_rate}%"
      }
    end

    if rate_limit_count > max_rate_limit_errors
      violations << {
        type: :rate_limit,
        value: rate_limit_count,
        threshold: max_rate_limit_errors,
        message: "Rate limit errors: #{rate_limit_count} (threshold: #{max_rate_limit_errors})"
      }
    end

    if spam_block_count > max_spam_blocks
      violations << {
        type: :spam_block,
        value: spam_block_count,
        threshold: max_spam_blocks,
        message: "Spam blocks: #{spam_block_count} (threshold: #{max_spam_blocks})"
      }
    end

    if user_not_found_count > max_user_not_found_errors
      violations << {
        type: :user_not_found,
        value: user_not_found_count,
        threshold: max_user_not_found_errors,
        message: "User not found errors: #{user_not_found_count} (threshold: #{max_user_not_found_errors})"
      }
    end

    violations.any? ? violations : false
  end

  # Проверка: нужно ли отправлять email уведомления
  def notify_email?
    notification_email.present?
  end
end

