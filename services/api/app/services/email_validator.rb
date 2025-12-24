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

      allowed = allowed_domains
      return error('From email domain is not authorized') if allowed.empty?
      return error('From email domain is not authorized') unless allowed.include?(domain)
      return error('AMS domain not allowed as sender') if domain.downcase.include?('ams')

      success
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
