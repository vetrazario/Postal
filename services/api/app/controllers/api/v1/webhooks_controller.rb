class Api::V1::WebhooksController < Api::V1::ApplicationController
  skip_before_action :authenticate_api_key
  before_action :verify_postal_signature, only: [:postal]

  def postal
    event = params[:event]
    payload = params[:payload] || {}
    message_id = payload.dig(:message, :id)&.to_s || payload.dig('message', 'id')&.to_s || payload.dig(:message, 'id')&.to_s || payload.dig('message', :id)&.to_s

    email_log = EmailLog.find_by(postal_message_id: message_id)
    
    unless email_log
      Rails.logger.warn "Webhook: email_log not found for postal_message_id: #{message_id}"
      return render json: { received: true }, status: :ok
    end

    process_webhook_event(email_log, event, payload)
    render json: { received: true }, status: :ok
  rescue StandardError => e
    Rails.logger.error "Webhook error: #{e.message}"
    render json: { received: true }, status: :ok
  end

  private

  def process_webhook_event(email_log, event, payload)
    case event
    when 'MessageDelivered'
      email_log.update_status('delivered', details: payload)
      TrackingEvent.create_event(email_log: email_log, event_type: 'delivered', event_data: payload)
      ReportToAmsJob.perform_later(email_log.external_message_id, 'delivered')

    when 'MessageBounced', 'MessageDeliveryFailed'
      # Классифицировать ошибку
      error_info = ErrorClassifier.classify(payload)
      
      # Обновить email_log с классификацией
      # MessageDeliveryFailed должен быть 'failed', а не 'bounced'
      status = event == 'MessageDeliveryFailed' ? 'failed' : 'bounced'
      email_log.update_status(status, details: payload)
      email_log.update(
        bounce_category: error_info[:category].to_s,
        smtp_code: error_info[:smtp_code],
        smtp_message: error_info[:message]
      )
      
      # Создать запись DeliveryError
      if email_log.campaign_id.present?
        DeliveryError.create!(
          email_log: email_log,
          campaign_id: email_log.campaign_id,
          category: error_info[:category].to_s,
          smtp_code: error_info[:smtp_code],
          smtp_message: error_info[:message],
          recipient_domain: email_log.recipient&.split('@')&.last
        )
        
        # Проверить пороги асинхронно
        CheckMailingThresholdsJob.perform_later(email_log.campaign_id)
      end
      
      TrackingEvent.create_event(email_log: email_log, event_type: 'bounce', event_data: payload)
      ReportToAmsJob.perform_later(email_log.external_message_id, 'bounced')

    when 'MessageHeld'
      email_log.update_status('failed', details: payload)
      ReportToAmsJob.perform_later(email_log.external_message_id, 'failed', 'Message held')
    end
  end

  def verify_postal_signature
    raw_body = read_raw_body
    signature = request.headers['X-Postal-Signature'].to_s

    return head(:unauthorized) if signature.blank?

    public_key = load_public_key
    return head(:unauthorized) unless public_key

    # TODO: Fix Postal webhook signature verification
    # EncryptoSigno doesn't work correctly with Postal's RSA signature format
    # Temporarily disabled until proper verification is implemented
    # unless public_key.verify(OpenSSL::Digest::SHA1.new, Base64.decode64(signature), raw_body)
    #   Rails.logger.warn "Invalid webhook signature from #{request.remote_ip}"
    #   return head(:unauthorized)
    # end

    request.body.rewind if request.body.respond_to?(:rewind)
  end

  def read_raw_body
    return request.env['RAW_POST_DATA'] if request.env['RAW_POST_DATA'].present?
    return request.raw_post if request.raw_post.present?

    request.body.rewind if request.body.respond_to?(:rewind)
    request.body.read
  end

  def load_public_key
    file_path = ENV.fetch('POSTAL_WEBHOOK_PUBLIC_KEY_FILE', nil)
    return nil if file_path.blank? || !File.exist?(file_path)

    pem = File.read(file_path)
    OpenSSL::PKey.read(pem)
  rescue OpenSSL::PKey::PKeyError, Errno::ENOENT => e
    Rails.logger.error "Invalid POSTAL_WEBHOOK_PUBLIC_KEY_FILE: #{e.message}"
    nil
  end
end
