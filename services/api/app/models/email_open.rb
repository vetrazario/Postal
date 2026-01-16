class EmailOpen < ApplicationRecord
  belongs_to :email_log

  validates :campaign_id, presence: true, length: { maximum: 255 }
  validates :token, presence: true, uniqueness: true
  validates :user_agent, length: { maximum: 1024 }, allow_nil: true
  validates :ip_address, length: { maximum: 45 }, allow_nil: true  # IPv6 max = 45 chars (with brackets)
  # opened_at is nullable - заполняется при первом открытии (не требуем presence)

  scope :for_campaign, ->(campaign_id) { where(campaign_id: campaign_id) }
  scope :opened, -> { where.not(opened_at: nil) } # Только реально открытые
  scope :recent, -> { where.not(opened_at: nil).order(opened_at: :desc) }
  scope :since, ->(time) { where('opened_at >= ?', time) }
  scope :unique_opens, -> {
    where.not(opened_at: nil)
      .select('DISTINCT ON (email_log_id) *')
      .order('email_log_id, opened_at')
  }

  # Generate unique token for tracking
  def self.generate_token
    loop do
      token = SecureRandom.urlsafe_base64(32)
      break token unless exists?(token: token)
    end
  end
end
