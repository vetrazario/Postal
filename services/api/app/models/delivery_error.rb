# frozen_string_literal: true

class DeliveryError < ApplicationRecord
  belongs_to :email_log

  ERROR_TYPES = %w[
    rate_limit
    spam_block
    user_not_found
    mailbox_full
    temporary
    authentication
    connection
    unknown
  ].freeze

  validates :error_type, presence: true, inclusion: { in: ERROR_TYPES }
  validates :occurred_at, presence: true

  before_validation :set_occurred_at, on: :create

  scope :by_email_log, ->(email_log_id) { where(email_log_id: email_log_id) }
  scope :by_type, ->(error_type) { where(error_type: error_type) }
  scope :by_category, ->(category) { where(error_type: category) }
  scope :recent, ->(minutes = 60) { where('created_at > ?', minutes.minutes.ago) }
  scope :in_window, ->(minutes) { where('created_at > ?', minutes.minutes.ago) }

  # Alias for backwards compatibility
  def category
    error_type
  end

  def self.count_by_type(email_log_id: nil, error_type: nil, window_minutes: 60)
    scope = in_window(window_minutes)
    scope = scope.by_email_log(email_log_id) if email_log_id.present?
    scope = scope.by_type(error_type) if error_type.present?
    scope.group(:error_type).count
  end

  private

  def set_occurred_at
    self.occurred_at ||= Time.current
  end
end

