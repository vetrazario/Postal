# frozen_string_literal: true

class EmailClick < ApplicationRecord
  belongs_to :email_log

  # Validations
  validates :email_log_id, presence: true
  validates :url, presence: true
  validates :token, presence: true, uniqueness: true
  validates :campaign_id, presence: true

  # Generate unique token for tracking
  def self.generate_token
    SecureRandom.urlsafe_base64(32)
  end

  # Scopes
  scope :clicked, -> { where.not(clicked_at: nil) }
  scope :unclicked, -> { where(clicked_at: nil) }
  scope :by_campaign, ->(campaign_id) { where(campaign_id: campaign_id) }
  scope :recent, -> { order(created_at: :desc) }
end
