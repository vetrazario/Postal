# frozen_string_literal: true

class EmailClick < ApplicationRecord
  belongs_to :email_log, optional: true

  # Validations
  validates :url, presence: true
  validates :token, presence: true, uniqueness: true

  # Set default campaign_id before validation
  before_validation :set_default_campaign_id

  # Generate unique token for tracking
  def self.generate_token
    SecureRandom.urlsafe_base64(32)
  end

  # Scopes
  scope :clicked, -> { where.not(clicked_at: nil) }
  scope :unclicked, -> { where(clicked_at: nil) }
  scope :by_campaign, ->(campaign_id) { where(campaign_id: campaign_id) }
  scope :recent, -> { order(created_at: :desc) }

  private

  def set_default_campaign_id
    self.campaign_id ||= email_log&.campaign_id || 'unknown'
  end
end
