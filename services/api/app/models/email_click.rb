class EmailClick < ApplicationRecord
  belongs_to :email_log

  validates :campaign_id, presence: true
  validates :url, presence: true
  validates :token, presence: true, uniqueness: true
  # clicked_at is nullable - заполняется при первом клике (не требуем presence)

  scope :for_campaign, ->(campaign_id) { where(campaign_id: campaign_id) }
  scope :clicked, -> { where.not(clicked_at: nil) } # Только реально кликнутые
  scope :recent, -> { where.not(clicked_at: nil).order(clicked_at: :desc) }
  scope :since, ->(time) { where('clicked_at >= ?', time) }

  # Generate unique token for tracking
  def self.generate_token
    loop do
      token = SecureRandom.urlsafe_base64(32)
      break token unless exists?(token: token)
    end
  end
end
