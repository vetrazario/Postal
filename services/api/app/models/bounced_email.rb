# frozen_string_literal: true

class BouncedEmail < ApplicationRecord
  validates :email, presence: true
  validates :bounce_type, presence: true, inclusion: { in: %w[hard soft] }
  validates :bounce_category, inclusion: { 
    in: %w[user_not_found spam_block mailbox_full authentication rate_limit temporary connection unknown],
    allow_nil: true
  }
  validates :smtp_code, length: { maximum: 10 }, allow_nil: true
  validates :smtp_message, length: { maximum: 1000 }, allow_nil: true
  validates :first_bounced_at, presence: true
  validates :last_bounced_at, presence: true

  scope :hard, -> { where(bounce_type: 'hard') }
  scope :soft, -> { where(bounce_type: 'soft') }
  scope :global, -> { where(campaign_id: nil) }
  scope :by_campaign, ->(campaign_id) { where(campaign_id: campaign_id) }
  scope :recent, -> { order(last_bounced_at: :desc) }
  scope :by_category, ->(category) { where(bounce_category: category) }
  scope :recent_hard, -> { where(bounce_type: 'hard').order(last_bounced_at: :desc) }
  scope :with_campaign_id, -> { where.not(campaign_id: nil) }
  scope :without_campaign_id, -> { where(campaign_id: nil) }
  scope :last_bounced_since, ->(time) { where('last_bounced_at >= ?', time) }

  # Проверка: заблокирован ли email?
  def self.blocked?(email:, campaign_id: nil)
    # Hard bounces блокируют всегда
    # Проверяем глобальный блок (campaign_id = null) или блок для конкретной кампании
    query = where(email: email, bounce_type: 'hard')
    
    if campaign_id.present?
      # Проверяем блок для конкретной кампании ИЛИ глобальный блок
      query = query.where('campaign_id = ? OR campaign_id IS NULL', campaign_id)
    else
      # Проверяем только глобальный блок
      query = query.where(campaign_id: nil)
    end
    
    query.exists?
  end

  # Добавить bounce ТОЛЬКО если нужно (не для rate_limit/temporary/connection)
  def self.record_bounce_if_needed(email:, bounce_category: nil, smtp_code: nil, smtp_message: nil, campaign_id: nil)
    # Не добавлять для rate_limit, temporary, connection
    return nil if ErrorClassifier::NON_BOUNCE_CATEGORIES.include?(bounce_category.to_s)
    
    record_bounce(
      email: email,
      bounce_type: 'hard',
      bounce_category: bounce_category,
      smtp_code: smtp_code,
      smtp_message: smtp_message,
      campaign_id: campaign_id
    )
  end

  # Добавить/обновить bounce
  def self.record_bounce(email:, bounce_type:, bounce_category: nil, smtp_code: nil, smtp_message: nil, campaign_id: nil)
    bounced = find_or_initialize_by(email: email, campaign_id: campaign_id)
    
    if bounced.new_record?
      bounced.assign_attributes(
        bounce_type: bounce_type,
        bounce_category: bounce_category,
        smtp_code: smtp_code,
        smtp_message: smtp_message,
        first_bounced_at: Time.current,
        last_bounced_at: Time.current,
        bounce_count: 1
      )
    else
      # Обновляем только если категория изменилась
      if bounce_category && bounced.bounce_category != bounce_category
        bounced.bounce_category = bounce_category
        bounced.smtp_code = smtp_code
        bounced.smtp_message = smtp_message
      end
      bounced.last_bounced_at = Time.current
      bounced.bounce_count += 1
    end
    
    bounced.save!
    bounced
  end

  # Получить описание статуса для CSV экспорта
  def status_description
    case bounce_category
    when 'user_not_found'
      'Hard: Not Found'
    when 'mailbox_full'
      'Hard: Mailbox Full'
    when 'spam_block'
      'Hard: Spam Block'
    when 'authentication'
      'Hard: Auth Fail'
    when 'rate_limit'
      'Rate Limited'
    when 'temporary'
      'Temporary Error'
    when 'connection'
      'Connection Error'
    else
      "Hard: #{bounce_category&.titleize || 'Unknown'}"
    end
  end
end

