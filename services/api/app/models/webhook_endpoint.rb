# frozen_string_literal: true

class WebhookEndpoint < ApplicationRecord
  # Associations
  has_many :webhook_logs, dependent: :destroy

  # Validations
  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }
  validates :retry_count, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 10 }
  validates :timeout, numericality: { greater_than: 0, less_than_or_equal_to: 120 }

  # Scopes
  scope :active, -> { where(active: true) }
  scope :for_event, ->(event_type) { where("events::jsonb @> ?", [event_type].to_json) }

  # Default events
  DEFAULT_EVENTS = %w[delivered opened clicked bounced failed complained unsubscribed].freeze

  # Check if event should be sent
  def should_send_event?(event_type)
    active? && events.include?(event_type.to_s)
  end

  # Send webhook
  def send_webhook(event_type, data)
    return unless should_send_event?(event_type)

    start_time = Time.current

    begin
      response = HTTP.timeout(timeout)
                     .headers(build_headers)
                     .post(url, json: {
                       event_type: event_type,
                       timestamp: Time.current.iso8601,
                       data: data
                     })

      duration = ((Time.current - start_time) * 1000).round(2)

      log_delivery(
        event_type: event_type,
        message_id: data[:message_id],
        response_code: response.code,
        response_body: response.body.to_s.truncate(1000),
        success: response.code.between?(200, 299),
        delivered_at: Time.current,
        duration_ms: duration
      )

      increment_successful! if response.code.between?(200, 299)
      increment_failed! unless response.code.between?(200, 299)

      response.code.between?(200, 299)

    rescue => e
      duration = ((Time.current - start_time) * 1000).round(2)

      log_delivery(
        event_type: event_type,
        message_id: data[:message_id],
        success: false,
        error_message: e.message,
        duration_ms: duration
      )

      increment_failed!
      false
    end
  end

  # Increment counters
  def increment_successful!
    increment!(:successful_deliveries)
    update_column(:last_success_at, Time.current)
  end

  def increment_failed!
    increment!(:failed_deliveries)
    update_column(:last_failure_at, Time.current)
  end

  # Success rate
  def success_rate
    total = successful_deliveries + failed_deliveries
    return 0 if total.zero?

    ((successful_deliveries.to_f / total) * 100).round(2)
  end

  # Recent logs
  def recent_logs(limit = 100)
    webhook_logs.order(created_at: :desc).limit(limit)
  end

  private

  def build_headers
    headers = {
      'Content-Type' => 'application/json',
      'User-Agent' => 'EmailSender-Webhook/1.0'
    }

    if secret_key.present?
      headers['X-Webhook-Signature'] = generate_signature
    end

    headers
  end

  def generate_signature
    # HMAC signature for webhook verification
    OpenSSL::HMAC.hexdigest('SHA256', secret_key, url)
  end

  def log_delivery(attributes)
    webhook_logs.create!(attributes)
  end
end
