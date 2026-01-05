class TrackingEvent < ApplicationRecord
  belongs_to :email_log

  validates :event_type, presence: true, inclusion: { in: %w[open click bounce complaint delivered unsubscribe] }
  validates :email_log_id, presence: true

  # Create event with IP and user agent
  def self.create_event(email_log:, event_type:, event_data: nil, ip_address: nil, user_agent: nil)
    create!(
      email_log: email_log,
      event_type: event_type,
      event_data: event_data,
      ip_address: ip_address,
      user_agent: user_agent
    )
  end
end





