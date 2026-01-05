# frozen_string_literal: true

class BouncedEmail < ApplicationRecord
  validates :email, presence: true
  validates :bounce_type, presence: true, inclusion: { in: %w[hard soft] }
  validates :first_bounced_at, presence: true
  validates :last_bounced_at, presence: true

  scope :hard, -> { where(bounce_type: 'hard') }
  scope :soft, -> { where(bounce_type: 'soft') }
  scope :global, -> { where(campaign_id: nil) }
  scope :by_campaign, ->(campaign_id) { where(campaign_id: campaign_id) }
  scope :recent, -> { order(last_bounced_at: :desc) }

  # Проверка: заблокирован ли email?
  def self.blocked?(email:, campaign_id: nil)
    # Hard bounces блокируют всегда (глобально)
    return true if exists?(email: email, bounce_type: 'hard', campaign_id: [campaign_id, nil].compact)
    
    # Soft bounces блокируют только для конкретной кампании (если указана)
    if campaign_id.present?
      return true if exists?(email: email, bounce_type: 'soft', campaign_id: campaign_id)
    end
    
    false
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
      # Обновляем если новый bounce более серьезный (soft -> hard)
      if bounce_type == 'hard' && bounced.bounce_type == 'soft'
        bounced.bounce_type = 'hard'
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
end

