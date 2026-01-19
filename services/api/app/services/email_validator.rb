class EmailValidator
  EMAIL_REGEX = /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i

  class << self
    def validate(recipient:, from_email:)
      result = validate_recipient(recipient)
      return result unless result[:valid]

      validate_sender_domain(from_email)
    end

    def validate_recipient(email)
      return error('Recipient email is required') if email.blank?
      return error('Recipient email is invalid') unless email.match?(EMAIL_REGEX)

      success
    end

    def validate_sender_domain(from_email)
      return error('From email is required') if from_email.blank?

      domain = from_email.split('@').last
      return error('From email domain is invalid') if domain.blank?

      # Проверить MX запись домена (опционально, для production)
      mx_validation = validate_mx_record(domain)
      return mx_validation unless mx_validation[:valid]

      allowed = allowed_domains

      # Handle empty ALLOWED_SENDER_DOMAINS
      if allowed.empty?
        Rails.logger.warn("⚠️  ALLOWED_SENDER_DOMAINS not set - accepting all domains (INSECURE!)")
        # In production, require explicit configuration
        if Rails.env.production?
          return error('ALLOWED_SENDER_DOMAINS must be configured in production')
        end
      elsif !allowed.include?(domain)
        return error('From email domain is not authorized')
      end

      return error('AMS domain not allowed as sender') if domain.downcase.include?('ams')

      success
    end

    # Проверить MX запись домена (зашита от отправки на несуществующие домены)
    def validate_mx_record(domain)
      return success if Rails.env.test? || Rails.env.development? # пропустить в тестах и разработке

      mx_records = Resolv::DNS.open.getresources(domain, Resolv::DNS::Resource::IN::MX) rescue []
      return error('Domain has no MX records') if mx_records.empty?

      success
    rescue Resolv::ResolvError => e
      error("DNS lookup failed: #{e.message}")
    end

    private

    def allowed_domains
      ENV.fetch('ALLOWED_SENDER_DOMAINS', '').split(',').map(&:strip)
    end

    def success
      { valid: true }
    end

    def error(message)
      { valid: false, error: message }
    end
  end
end
