class EmailLog < ApplicationRecord
  STATUSES = %w[queued processing sent delivered bounced failed complained].freeze

  belongs_to :template, class_name: 'EmailTemplate', optional: true
  has_many :tracking_events, dependent: :destroy
  has_many :delivery_errors, dependent: :destroy

  validates :message_id, presence: true, uniqueness: true
  validates :recipient, presence: true
  validates :recipient_masked, presence: true
  validates :sender, presence: true
  validates :subject, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  # external_message_id and campaign_id are optional (not all emails have campaigns)

  encrypts :recipient, deterministic: true

  def self.mask_email(email)
    return email if email.blank?

    local, domain = email.split('@', 2)
    return email if local.blank? || domain.blank?

    masked = local.length <= 2 ? "#{local[0]}***" : "#{local[0]}***#{local[-1]}"
    "#{masked}@#{domain}"
  end

  def recipient=(value)
    super(value)
    self.recipient_masked = self.class.mask_email(value) if value.present?
  end

  def update_status(new_status, details: nil)
    attrs = { status: new_status, status_details: details }
    attrs[:sent_at] = Time.current if new_status == 'sent'
    attrs[:delivered_at] = Time.current if new_status == 'delivered'
    update!(attrs)
  end
end
