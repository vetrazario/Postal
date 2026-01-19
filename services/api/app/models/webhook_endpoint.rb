# frozen_string_literal: true

class WebhookEndpoint < ApplicationRecord
  # Associations
  has_many :webhook_logs, dependent: :destroy

  # Validations
  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }
  validates :secret, presence: true

  # Scopes
  scope :active, -> { where(active: true) }
  scope :for_event, ->(event_type) { where("events::jsonb @> ?", [event_type].to_json) }

  # Default events
  DEFAULT_EVENTS = %w[delivered opened clicked bounced failed complained unsubscribed].freeze

  # Initialize with default events
  after_initialize do
    self.events ||= DEFAULT_EVENTS
    self.headers ||= {}
  end

  # Check if event should be sent
  def should_send_event?(event_type)
    active? && events.include?(event_type.to_s)
  end

  # Send webhook
  def send_webhook(event_type, data)
    return unless should_send_event?(event_type)

    start_time = Time.current

    begin
      body = {
        event_type: event_type,
        timestamp: Time.current.iso8601,
        data: data
      }

      response = HTTParty.post(
        url,
        headers: build_headers(body),
        body: body.to_json,
        timeout: 30,
        verify: true
      )

      log_delivery(
        event_type: event_type,
        payload: body,
        status_code: response.code,
        response_body: response.body.to_s.truncate(1000),
        sent_at: Time.current
      )

      response.code.between?(200, 299)

    rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError => e
      log_delivery(
        event_type: event_type,
        payload: body,
        error_message: e.message,
        sent_at: Time.current
      )

      false
    end
  end

  # Recent logs
  def recent_logs(limit = 100)
    webhook_logs.order(created_at: :desc).limit(limit)
  end

  private

  def build_headers(body)
    request_headers = {
      'Content-Type' => 'application/json',
      'User-Agent' => 'EmailSender-Webhook/1.0'
    }

    # Merge custom headers
    request_headers.merge!(headers) if headers.present?

    # Add HMAC signature
    if secret.present?
      signature = OpenSSL::HMAC.hexdigest('SHA256', secret, body.to_json)
      request_headers['X-Webhook-Signature'] = "sha256=#{signature}"
    end

    request_headers
  end

  def log_delivery(attributes)
    webhook_logs.create!(attributes)
  end
end
