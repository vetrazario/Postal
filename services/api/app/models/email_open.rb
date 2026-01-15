class EmailOpen < ApplicationRecord
  belongs_to :email_log

  validates :campaign_id, presence: true
  validates :token, presence: true, uniqueness: true
  validates :opened_at, presence: true

  scope :for_campaign, ->(campaign_id) { where(campaign_id: campaign_id) }
  scope :recent, -> { order(opened_at: :desc) }
  scope :since, ->(time) { where('opened_at >= ?', time) }
  scope :unique_opens, -> { select('DISTINCT ON (email_log_id) *').order('email_log_id, opened_at') }

  # Generate unique token for tracking
  def self.generate_token
    loop do
      token = SecureRandom.urlsafe_base64(32)
      break token unless exists?(token: token)
    end
  end
end
