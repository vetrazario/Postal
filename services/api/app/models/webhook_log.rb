# frozen_string_literal: true

class WebhookLog < ApplicationRecord
  # Associations
  belongs_to :webhook_endpoint

  # Validations
  validates :event_type, presence: true

  # Scopes
  scope :successful, -> { where('status_code BETWEEN 200 AND 299') }
  scope :failed, -> { where('status_code IS NULL OR status_code NOT BETWEEN 200 AND 299') }
  scope :for_event, ->(event_type) { where(event_type: event_type) }
  scope :recent, -> { order(created_at: :desc) }

  # Check if delivery was successful
  def success?
    status_code.present? && status_code.between?(200, 299)
  end

  # Response status
  def response_status
    return 'error' unless status_code

    case status_code
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

  # Should retry?
  def should_retry?
    !success? && retry_count < 3
  end

  # Retry webhook delivery
  def retry!
    return false unless should_retry?

    increment!(:retry_count)

    webhook_endpoint.send_webhook(event_type, payload.merge(
      retried: true,
      retry_attempt: retry_count
    ))
  end
end
