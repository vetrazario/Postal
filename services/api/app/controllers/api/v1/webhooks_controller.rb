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
      
      # Обновить статистику кампании
      if email_log.campaign_id.present?
        CampaignStats.find_or_initialize_for(email_log.campaign_id).increment_delivered
      end
      
      ReportToAmsJob.perform_later(email_log.external_message_id, 'delivered')
      Rails.logger.info "MessageSent->Delivered: #{email_log.recipient_masked} - #{smtp_code} - #{smtp_details}"

    when 'MessageDelivered'
      email_log.update_status('delivered', details: payload)
      TrackingEvent.create_event(email_log: email_log, event_type: 'delivered', event_data: payload)
      
      # Обновить статистику кампании
      if email_log.campaign_id.present?
        CampaignStats.find_or_initialize_for(email_log.campaign_id).increment_delivered
      end
      
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
      
      # Добавить в bounce list ТОЛЬКО если нужно
      if error_info[:should_add_to_bounce]
        BouncedEmail.record_bounce_if_needed(
          email: email_log.recipient,
          bounce_category: error_info[:category],
          smtp_code: error_info[:smtp_code],
          smtp_message: error_info[:message],
          campaign_id: email_log.campaign_id
        )
      end
      
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
        
        # Проверить пороги асинхронно (останавливает рассылку если нужно)
        CheckMailingThresholdsJob.perform_later(email_log.campaign_id)
      end
      
      TrackingEvent.create_event(email_log: email_log, event_type: 'bounce', event_data: payload)
      
      # Обновить статистику кампании
      if email_log.campaign_id.present?
        CampaignStats.find_or_initialize_for(email_log.campaign_id).increment_bounced
      end
      
      # Отправить webhook в AMS с полными данными
      ReportToAmsJob.perform_later(
        email_log.external_message_id,
        'bounced',
        nil,
        {
          bounce_category: error_info[:category],
          smtp_code: error_info[:smtp_code],
          smtp_message: error_info[:message],
          should_add_to_bounce: error_info[:should_add_to_bounce],
          should_stop_mailing: error_info[:should_stop_mailing]
        }
      )

    when 'MessageHeld'
      # Письмо заблокировано (suppression list, rate limit, etc.)
      held_reason = payload['details'] || payload[:details] || 'Message held'

      email_log.update_status('failed', details: payload)

      # Создать запись DeliveryError
      if email_log.campaign_id.present?
        # Определить категорию ошибки
        category = if held_reason.to_s.downcase.include?('suppression')
                     'user_not_found'
                   elsif held_reason.to_s.downcase.include?('rate') || held_reason.to_s.downcase.include?('limit')
                     'rate_limit'
                   elsif held_reason.to_s.downcase.include?('spam')
                     'spam_block'
                   else
                     'temporary'
                   end

        DeliveryError.create!(
          email_log: email_log,
          campaign_id: email_log.campaign_id,
          category: category,
          smtp_code: nil,
          smtp_message: held_reason.to_s.truncate(1000),
          recipient_domain: email_log.recipient&.split('@')&.last
        )

        Rails.logger.info "DeliveryError created for MessageHeld: campaign=#{email_log.campaign_id}, reason=#{held_reason}"
      end

      ReportToAmsJob.perform_later(email_log.external_message_id, 'failed', 'Message held')

    when 'MessageComplained'
      Rails.logger.info "MessageComplained received for #{email_log.message_id}"
      
      # Обновить статус email_log
      email_log.update_status('complained', details: payload)
      
      # Создать tracking event
      TrackingEvent.create_event(email_log: email_log, event_type: 'complaint', event_data: payload)
      
      # Обновить статистику кампании
      if email_log.campaign_id.present?
        CampaignStats.find_or_initialize_for(email_log.campaign_id).increment_complained
      end
      
      # Отправить webhook в AMS
      ReportToAmsJob.perform_later(email_log.external_message_id, 'complained')
      
      Rails.logger.info "Complaint recorded for #{email_log.recipient_masked}"

    when 'MessageLoaded'
      # Email был открыт (tracking pixel загружен)
      email_log.update(delivered_at: Time.current) unless email_log.delivered_at
      TrackingEvent.create_event(email_log: email_log, event_type: 'open', event_data: payload)
      Rails.logger.info "MessageLoaded (opened): #{email_log.recipient_masked}"

    when 'MessageLinkClicked'
      # Клик по ссылке
      url = payload['url'] || payload[:url]
      TrackingEvent.create_event(email_log: email_log, event_type: 'click', event_data: payload)
      # Маскируем URL для безопасности (может содержать токены)
      url_masked = url&.split('?')&.first || url
      Rails.logger.info "MessageLinkClicked: #{email_log.recipient_masked} -> #{url_masked}"

    else
      Rails.logger.warn "Unknown webhook event: #{event}"
    end
  end

  def verify_postal_signature
    raw_body = read_raw_body
    signature_header = request.headers['X-Postal-Signature'].to_s

    # Skip verification if disabled via ENV (for testing only)
    if ENV['SKIP_POSTAL_WEBHOOK_VERIFICATION'] == 'true'
      Rails.logger.warn "Webhook signature verification SKIPPED (testing mode) from #{request.remote_ip}"
      request.body.rewind if request.body.respond_to?(:rewind)
      return
    end

    # Log verification attempt
    Rails.logger.info "Webhook verification attempt from #{request.remote_ip}"
    Rails.logger.debug "Signature header present: #{signature_header.present?}, Body length: #{raw_body&.length}"

    # Validate request body
    unless raw_body.is_a?(String) && raw_body.present?
      Rails.logger.error "Invalid request body from #{request.remote_ip} - body is nil or empty"
      return head(:unauthorized)
    end

    if signature_header.blank?
      Rails.logger.warn "Missing webhook signature from #{request.remote_ip}"
      return head(:unauthorized)
    end

    public_key = load_public_key
    unless public_key
      Rails.logger.error "Postal public key not configured - rejecting webhook from #{request.remote_ip}"
      return head(:unauthorized)
    end

    # Postal uses RSA-SHA256 for webhook signatures
    # Format: "sha256=<base64_signature>" or just "<base64_signature>"
    begin
      # Extract and validate signature format
      if signature_header.start_with?('sha256=')
        signature_base64 = signature_header[7..]  # Remove "sha256=" prefix (7 chars)
      elsif signature_header.match?(/^[A-Za-z0-9+\/=]+$/)  # Pure base64 (no prefix)
        signature_base64 = signature_header
      else
        Rails.logger.warn "Invalid signature format from #{request.remote_ip} (expected 'sha256=...' or base64)"
        return head(:unauthorized)
      end
      
      decoded_signature = Base64.decode64(signature_base64)
      
      # RSA signatures have fixed length based on key size
      # RSA-2048 = 256 bytes (standard), RSA-4096 = 512 bytes
      # Postal uses RSA-2048, so we expect exactly 256 bytes
      unless decoded_signature.length == 256
        Rails.logger.warn "Invalid signature length: #{decoded_signature.length} bytes from #{request.remote_ip} (expected exactly 256 bytes for RSA-2048)"
        return head(:unauthorized)
      end
      
      Rails.logger.debug "Decoded signature length: #{decoded_signature.length} bytes"
      
      # Postal uses ONLY RSA-SHA256 for webhook signatures (SHA1 is cryptographically broken)
      verified = public_key.verify(OpenSSL::Digest::SHA256.new, decoded_signature, raw_body)

      unless verified
        Rails.logger.warn "Invalid webhook signature from #{request.remote_ip} - signature verification failed"
        return head(:unauthorized)
      end
      
      Rails.logger.info "Webhook signature verified successfully from #{request.remote_ip}"
    rescue OpenSSL::PKey::RSAError, ArgumentError => e
      Rails.logger.error "Signature verification error from #{request.remote_ip}: #{e.class.name} - #{e.message}"
      return head(:unauthorized)
    rescue StandardError => e
      Rails.logger.error "Unexpected error during signature verification from #{request.remote_ip}: #{e.class.name} - #{e.message}"
      return head(:unauthorized)
    end

    request.body.rewind if request.body.respond_to?(:rewind)
  end

  def read_raw_body
    # Use request.raw_post which caches the body and doesn't interfere with params parsing
    # This is safe to call before params are parsed
    body = request.raw_post
    return body if body.present?
    
    # Fallback for older Rails versions
    if request.env['RAW_POST_DATA'].present?
      return request.env['RAW_POST_DATA']
    end
    
    # Last resort - read body directly (may break params parsing!)
    # Only use if absolutely necessary
    request.body.rewind if request.body.respond_to?(:rewind)
    body = request.body.read
    request.body.rewind if request.body.respond_to?(:rewind) # Rewind for params parsing
    body
  end

  def load_public_key
    file_path = ENV.fetch('POSTAL_WEBHOOK_PUBLIC_KEY_FILE', nil)
    
    if file_path.blank?
      Rails.logger.error "POSTAL_WEBHOOK_PUBLIC_KEY_FILE not configured"
      return nil
    end
    
    unless File.exist?(file_path)
      Rails.logger.error "Postal public key file not found: #{file_path}"
      return nil
    end

    pem = File.read(file_path)
    
    if pem.blank?
      Rails.logger.error "Postal public key file is empty: #{file_path}"
      return nil
    end
    
    key = OpenSSL::PKey.read(pem)
    Rails.logger.info "Postal public key loaded successfully from #{file_path}"
    key
  rescue OpenSSL::PKey::PKeyError => e
    Rails.logger.error "Invalid Postal public key format in #{file_path}: #{e.class.name} - #{e.message}"
    nil
  rescue Errno::ENOENT => e
    Rails.logger.error "Postal public key file not found: #{file_path} - #{e.message}"
    nil
  rescue StandardError => e
    Rails.logger.error "Error loading Postal public key from #{file_path}: #{e.class.name} - #{e.message}"
    nil
  end

end
