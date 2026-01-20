# frozen_string_literal: true

class WebhookLog < ApplicationRecord
  # Associations
  belongs_to :webhook_endpoint

  # Validations
  validates :event_type, presence: true

  # Scopes
  scope :successful, -> { where(success: true) }
  scope :failed, -> { where(success: false) }
  scope :for_event, ->(event_type) { where(event_type: event_type) }
  scope :recent, -> { order(created_at: :desc) }

  # Check if should retry
  def should_retry?
    !success && webhook_endpoint.retry_count > 0
  end

  # Retry webhook delivery
  def retry!
    return false unless should_retry?

    webhook_endpoint.send_webhook(event_type, {
      message_id: message_id,
      retried: true,
      original_attempt_id: id
    })
  end

  # Response status
  def response_status
    return 'error' unless response_code

    case response_code
    when 200..299
      'success'
    when 400..499
      'client_error'
    when 500..599
      'server_error'
    else
      'unknown'
    end
  end

  # Duration in seconds
  def duration_seconds
    return nil unless duration_ms

    (duration_ms / 1000.0).round(3)
  end
end
