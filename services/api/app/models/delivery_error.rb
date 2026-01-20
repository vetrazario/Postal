# frozen_string_literal: true

class DeliveryError < ApplicationRecord
  belongs_to :email_log

  CATEGORIES = %w[
    rate_limit
    spam_block
    user_not_found
    mailbox_full
    temporary
    authentication
    connection
    unknown
  ].freeze

  validates :category, presence: true, inclusion: { in: CATEGORIES }
  validates :campaign_id, presence: true

  scope :by_campaign, ->(campaign_id) { where(campaign_id: campaign_id) }
  scope :by_category, ->(category) { where(category: category) }
  scope :recent, ->(minutes = 60) { where('created_at > ?', minutes.minutes.ago) }
  scope :in_window, ->(minutes) { where('created_at > ?', minutes.minutes.ago) }

  def self.count_by_category(campaign_id: nil, category: nil, window_minutes: 60)
    scope = in_window(window_minutes)
    scope = scope.by_campaign(campaign_id) if campaign_id.present?
    scope = scope.by_category(category) if category.present?
    scope.group(:category).count
  end
end

