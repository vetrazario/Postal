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
    Rails.logger.info "Processing webhook event: #{event} for message_id: #{email_log.postal_message_id}"

    case event
    when 'MessageSent'
      # Postal "Sent" = письмо принято удаленным SMTP сервером = для нас это "delivered"
      smtp_output = payload['output'] || payload[:output]
      smtp_details = payload['details'] || payload[:details]
      delivery_time = payload['time'] || payload[:time]
      sent_with_ssl = payload['sent_with_ssl'] || payload[:sent_with_ssl]

      # Извлечь SMTP код из output (например "250 2.0.0 OK...")
      smtp_code = smtp_output&.match(/^(\d{3})/)&.[](1)

      email_log.update(
        status: 'delivered',  # Postal Sent = наш Delivered
        sent_at: Time.current,
        delivered_at: Time.current,
        smtp_code: smtp_code,
        smtp_message: "#{smtp_output}\n---\n#{smtp_details}",
        status_details: payload.merge(
          delivery_time_seconds: delivery_time,
          sent_with_ssl: sent_with_ssl
        )
      )

      TrackingEvent.create_event(email_log: email_log, event_type: 'delivered', event_data: payload)
      ReportToAmsJob.perform_later(email_log.external_message_id, 'delivered')
      Rails.logger.info "MessageSent->Delivered: #{email_log.recipient} - #{smtp_code} - #{smtp_details}"

    when 'MessageDelivered'
      email_log.update_status('delivered', details: payload)
      TrackingEvent.create_event(email_log: email_log, event_type: 'delivered', event_data: payload)
      ReportToAmsJob.perform_later(email_log.external_message_id, 'delivered')

    when 'MessageBounced', 'MessageDeliveryFailed'
      # Классифицировать ошибку
      error_info = ErrorClassifier.classify(payload)
      
      # Определить тип bounce (hard/soft)
      bounce_type = determine_bounce_type(error_info)
      
      # Обновить email_log с классификацией
      # MessageDeliveryFailed должен быть 'failed', а не 'bounced'
      status = event == 'MessageDeliveryFailed' ? 'failed' : 'bounced'
      email_log.update_status(status, details: payload)
      email_log.update(
        bounce_category: error_info[:category].to_s,
        smtp_code: error_info[:smtp_code],
        smtp_message: error_info[:message]
      )
      
      # Сохранить в таблицу bounced_emails
      BouncedEmail.record_bounce(
        email: email_log.recipient,
        bounce_type: bounce_type,
        bounce_category: error_info[:category].to_s,
        smtp_code: error_info[:smtp_code],
        smtp_message: error_info[:message],
        campaign_id: email_log.campaign_id
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

    when 'MessageLoaded'
      # Email был открыт (tracking pixel загружен)
      email_log.update(delivered_at: Time.current) unless email_log.delivered_at
      TrackingEvent.create_event(email_log: email_log, event_type: 'open', event_data: payload)
      Rails.logger.info "MessageLoaded (opened): #{email_log.recipient}"

    when 'MessageLinkClicked'
      # Клик по ссылке
      url = payload['url'] || payload[:url]
      TrackingEvent.create_event(email_log: email_log, event_type: 'click', event_data: payload)
      Rails.logger.info "MessageLinkClicked: #{email_log.recipient} -> #{url}"

    else
      Rails.logger.warn "Unknown webhook event: #{event}"
    end
  end

  def verify_postal_signature
    raw_body = read_raw_body
    signature = request.headers['X-Postal-Signature'].to_s

    # Skip verification if disabled via ENV (for testing only)
    if ENV['SKIP_POSTAL_WEBHOOK_VERIFICATION'] == 'true'
      Rails.logger.warn "Webhook signature verification SKIPPED (testing mode)"
      request.body.rewind if request.body.respond_to?(:rewind)
      return
    end

    if signature.blank?
      Rails.logger.warn "Missing webhook signature from #{request.remote_ip}"
      return head(:unauthorized)
    end

    public_key = load_public_key
    unless public_key
      Rails.logger.error "Postal public key not configured - rejecting webhook"
      return head(:unauthorized)
    end

    # Postal uses RSA-SHA256 for webhook signatures
    begin
      decoded_signature = Base64.decode64(signature)
      # Try SHA256 first (Postal's default), fallback to SHA1
      verified = public_key.verify(OpenSSL::Digest::SHA256.new, decoded_signature, raw_body) ||
                 public_key.verify(OpenSSL::Digest::SHA1.new, decoded_signature, raw_body)

      unless verified
        Rails.logger.warn "Invalid webhook signature from #{request.remote_ip}"
        return head(:unauthorized)
      end
    rescue OpenSSL::PKey::RSAError, ArgumentError => e
      Rails.logger.error "Signature verification error: #{e.class.name}"
      return head(:unauthorized)
    end

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

  def determine_bounce_type(error_info)
    # Hard bounces: permanent failures
    hard_categories = %w[user_not_found invalid_domain mailbox_full]
    return 'hard' if hard_categories.include?(error_info[:category].to_s)
    
    # Soft bounces: temporary failures
    'soft'
  end
end
