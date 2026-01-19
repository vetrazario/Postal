# frozen_string_literal: true

class Unsubscribe < ApplicationRecord
  validates :email, presence: true

  # Set defaults before validation
  before_validation :set_defaults

  scope :global, -> { where(campaign_id: nil) }
  scope :by_campaign, ->(campaign_id) { where(campaign_id: campaign_id) }
  scope :recent, -> { order(unsubscribed_at: :desc) }

  # Проверка: заблокирован ли email?
  def self.blocked?(email:, campaign_id: nil)
    # Проверяем глобальный unsubscribe (campaign_id = null)
    return true if exists?(email: email, campaign_id: nil)

    # Проверяем unsubscribe для конкретной кампании
    return true if campaign_id.present? && exists?(email: email, campaign_id: campaign_id)

    false
  end

  # Создать или обновить unsubscribe
  def self.record_unsubscribe(email:, campaign_id: nil, ip_address: nil, user_agent: nil, reason: 'user_request')
    unsubscribe = find_or_initialize_by(email: email, campaign_id: campaign_id)

    if unsubscribe.new_record?
      unsubscribe.assign_attributes(
        reason: reason,
        ip_address: ip_address,
        user_agent: user_agent,
        unsubscribed_at: Time.current
      )
    else
      # Обновляем только дату и IP если уже существует
      unsubscribe.update!(
        unsubscribed_at: Time.current,
        ip_address: ip_address,
        user_agent: user_agent
      )
    end

    unsubscribe.save!
    unsubscribe
  end

  private

  def set_defaults
    self.unsubscribed_at ||= Time.current
    self.reason ||= 'user_request'
  end
end
