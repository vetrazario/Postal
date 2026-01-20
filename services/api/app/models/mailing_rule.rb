# frozen_string_literal: true

class MailingRule < ApplicationRecord
  RULE_TYPES = %w[
    bounce_threshold
    rate_limit
    spam_filter
    domain_block
    custom
    global_settings
  ].freeze

  SINGLETON_NAME = 'Global Mailing Settings'.freeze

  validates :name, presence: true
  validates :rule_type, presence: true, inclusion: { in: RULE_TYPES }

  scope :active, -> { where(active: true) }
  scope :by_type, ->(type) { where(rule_type: type) }
  scope :by_priority, -> { order(priority: :desc) }

  # ==========================================
  # Singleton Pattern for Global Settings
  # ==========================================
  def self.instance
    find_or_create_by!(name: SINGLETON_NAME, rule_type: 'global_settings') do |rule|
      rule.conditions = default_conditions
      rule.actions = default_actions
      rule.active = true
      rule.priority = 1000
    end
  end

  def self.default_conditions
    {
      'max_bounce_rate' => 10.0,
      'max_rate_limit_errors' => 5,
      'max_spam_blocks' => 3,
      'check_window_minutes' => 60
    }
  end

  def self.default_actions
    {
      'auto_stop_mailing' => false,
      'notify_email' => false,
      'notification_email' => nil,
      'ams_api_url' => nil,
      'ams_api_key' => nil
    }
  end

  # ==========================================
  # Accessors for Global Settings (stored in JSONB)
  # ==========================================

  # Conditions accessors
  def max_bounce_rate
    conditions['max_bounce_rate']&.to_f || 10.0
  end

  def max_bounce_rate=(value)
    self.conditions = (conditions || {}).merge('max_bounce_rate' => value.to_f)
  end

  def max_rate_limit_errors
    conditions['max_rate_limit_errors']&.to_i || 5
  end

  def max_rate_limit_errors=(value)
    self.conditions = (conditions || {}).merge('max_rate_limit_errors' => value.to_i)
  end

  def max_spam_blocks
    conditions['max_spam_blocks']&.to_i || 3
  end

  def max_spam_blocks=(value)
    self.conditions = (conditions || {}).merge('max_spam_blocks' => value.to_i)
  end

  def check_window_minutes
    conditions['check_window_minutes']&.to_i || 60
  end

  def check_window_minutes=(value)
    self.conditions = (conditions || {}).merge('check_window_minutes' => value.to_i)
  end

  # Actions accessors
  def auto_stop_mailing
    actions['auto_stop_mailing'] == true
  end
  alias auto_stop_mailing? auto_stop_mailing

  def auto_stop_mailing=(value)
    self.actions = (actions || {}).merge('auto_stop_mailing' => value == true || value == '1' || value == 'true')
  end

  def notify_email
    actions['notify_email'] == true
  end
  alias notify_email? notify_email

  def notify_email=(value)
    self.actions = (actions || {}).merge('notify_email' => value == true || value == '1' || value == 'true')
  end

  def notification_email
    actions['notification_email']
  end

  def notification_email=(value)
    self.actions = (actions || {}).merge('notification_email' => value)
  end

  def ams_api_url
    actions['ams_api_url']
  end

  def ams_api_url=(value)
    self.actions = (actions || {}).merge('ams_api_url' => value)
  end

  def ams_api_key
    actions['ams_api_key']
  end

  def ams_api_key=(value)
    self.actions = (actions || {}).merge('ams_api_key' => value)
  end

  # ==========================================
  # Threshold Checking Logic
  # ==========================================
  def thresholds_exceeded?(campaign_id)
    return nil unless active?
    return nil unless campaign_id.present?

    window = check_window_minutes.minutes.ago
    violations = []

    # Get campaign delivery errors with proper join through email_log
    campaign_errors = DeliveryError
      .joins(:email_log)
      .where(email_logs: { campaign_id: campaign_id })
      .where('delivery_errors.created_at > ?', window)

    total_sent = EmailLog.where(campaign_id: campaign_id).where('created_at > ?', window).count
    return nil if total_sent == 0

    # Check bounce rate
    bounce_count = campaign_errors.where(error_type: %w[user_not_found mailbox_full temporary]).count
    bounce_rate = (bounce_count.to_f / total_sent * 100).round(2)
    if bounce_rate > max_bounce_rate
      violations << {
        type: :bounce_rate,
        message: "Bounce rate #{bounce_rate}% exceeds threshold #{max_bounce_rate}%",
        value: bounce_rate,
        threshold: max_bounce_rate
      }
    end

    # Check rate limit errors
    rate_limit_count = campaign_errors.where(error_type: 'rate_limit').count
    if rate_limit_count > max_rate_limit_errors
      violations << {
        type: :rate_limit,
        message: "Rate limit errors #{rate_limit_count} exceeds threshold #{max_rate_limit_errors}",
        value: rate_limit_count,
        threshold: max_rate_limit_errors
      }
    end

    # Check spam blocks
    spam_block_count = campaign_errors.where(error_type: 'spam_block').count
    if spam_block_count > max_spam_blocks
      violations << {
        type: :spam_block,
        message: "Spam blocks #{spam_block_count} exceeds threshold #{max_spam_blocks}",
        value: spam_block_count,
        threshold: max_spam_blocks
      }
    end

    violations.any? ? violations : nil
  end

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
