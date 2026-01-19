# frozen_string_literal: true

class MailingRule < ApplicationRecord
  RULE_TYPES = %w[
    bounce_threshold
    rate_limit
    spam_filter
    domain_block
    custom
  ].freeze

  validates :name, presence: true
  validates :rule_type, presence: true, inclusion: { in: RULE_TYPES }

  scope :active, -> { where(active: true) }
  scope :by_type, ->(type) { where(rule_type: type) }
  scope :by_priority, -> { order(priority: :desc) }

  # Get all active rules sorted by priority
  def self.active_rules
    active.by_priority
  end

  # Check if any rule matches the given conditions
  def self.matches?(email_log:, error_type: nil)
    active_rules.find do |rule|
      rule.matches?(email_log: email_log, error_type: error_type)
    end
  end

  # Check if this rule matches the given conditions
  def matches?(email_log:, error_type: nil)
    return false unless active?

    case rule_type
    when 'bounce_threshold'
      check_bounce_threshold(email_log)
    when 'rate_limit'
      check_rate_limit(email_log)
    when 'spam_filter'
      error_type == 'spam_block'
    when 'domain_block'
      check_domain_block(email_log)
    else
      check_custom_conditions(email_log, error_type)
    end
  end

  # Execute rule actions
  def execute_actions(email_log)
    actions.each do |action_type, action_params|
      case action_type.to_s
      when 'block_email'
        block_email(email_log)
      when 'notify'
        send_notification(email_log, action_params)
      when 'stop_campaign'
        stop_campaign(email_log.campaign_id)
      end
    end
  end

  private

  def check_bounce_threshold(email_log)
    threshold = conditions['bounce_count']&.to_i || 3
    window = conditions['window_minutes']&.to_i || 60

    bounce_count = DeliveryError
      .where(email_log_id: email_log.id)
      .where('created_at > ?', window.minutes.ago)
      .count

    bounce_count >= threshold
  end

  def check_rate_limit(email_log)
    max_emails = conditions['max_emails']&.to_i || 100
    window = conditions['window_minutes']&.to_i || 60

    recent_count = EmailLog
      .where(campaign_id: email_log.campaign_id)
      .where('created_at > ?', window.minutes.ago)
      .count

    recent_count >= max_emails
  end

  def check_domain_block(email_log)
    blocked_domains = conditions['domains'] || []
    domain = email_log.recipient.split('@').last
    blocked_domains.include?(domain)
  end

  def check_custom_conditions(email_log, error_type)
    # Custom rule evaluation based on conditions JSON
    return false if conditions.blank?

    conditions.all? do |field, expected|
      case field.to_s
      when 'error_type'
        error_type == expected
      when 'campaign_id'
        email_log.campaign_id == expected
      when 'status'
        email_log.status == expected
      else
        false
      end
    end
  end

  def block_email(email_log)
    BouncedEmail.record_bounce(
      email: email_log.recipient,
      bounce_type: 'hard',
      bounce_category: 'rule_blocked',
      campaign_id: email_log.campaign_id
    )
  end

  def send_notification(email_log, params)
    # TODO: Implement notification sending
    Rails.logger.info "MailingRule notification: #{params.inspect} for #{email_log.id}"
  end

  def stop_campaign(campaign_id)
    # TODO: Implement campaign stopping logic
    Rails.logger.warn "MailingRule: Stopping campaign #{campaign_id}"
  end
end
