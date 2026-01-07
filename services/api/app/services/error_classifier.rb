# frozen_string_literal: true

class ErrorClassifier
  ERROR_PATTERNS = {
    rate_limit: [
      'rate limit',
      'too many connections',
      '421',
      '429',
      'throttl',
      'connection rate limit',
      'too many messages',
      'receiving mail at a rate',
      '5.7.1.*rate.*limit'
    ],
    spam_block: [
      'spam',
      'blacklist',
      'blocked',
      'rejected',
      'dnsbl',
      'rbl',
      'spamhaus',
      'suspected spam',
      '550 5.7.1',
      'message has been blocked',
      'likely spam',
      'policy restrictions'
    ],
    user_not_found: [
      'user unknown',
      'mailbox not found',
      'does not exist',
      '550 5.1.1',
      'no such user',
      'recipient not found',
      'invalid recipient',
      'unable to find recipient'
    ],
    mailbox_full: [
      'mailbox full',
      'quota exceeded',
      'over quota',
      '552',
      'mailbox is full',
      'storage quota',
      '550 5.2.1',
      '552 5.2.2',
      'exceeded storage allocation'
    ],
    temporary: [
      'try again',
      'temporarily',
      '4.7.',
      'greylisted',
      'temporary failure',
      'try later',
      '421 4.7.0',
      '450 4.2.1',
      '451 4.5.1',
      'insufficient system storage'
    ],
    authentication: [
      'authentication',
      'spf',
      'dkim',
      'dmarc',
      'authentication failed',
      '550 5.7.23',
      'unauthenticated email is not accepted',
      'does not have authentication',
      'spf/dkim/dmarc failure',
      'tls required'
    ],
    connection: [
      'connection refused',
      'timeout',
      'unreachable',
      'connection error',
      'network error',
      'connection reset',
      'service not available',
      'closing transmission channel'
    ]
  }.freeze

  # Категории, которые НЕ добавлять в bounce list (проблемы скорости, а не качества адреса)
  NON_BOUNCE_CATEGORIES = %w[rate_limit temporary connection].freeze

  # Категории, при которых останавливать рассылку
  STOP_MAILING_CATEGORIES = %w[rate_limit spam_block mailbox_full temporary connection].freeze

  class << self
    def classify(payload)
      output = extract_text(payload, :output) || ''
      details = extract_text(payload, :details) || ''
      status = extract_text(payload, :status) || ''
      
      full_text = "#{status} #{output} #{details}".downcase
      
      category = find_category(full_text)
      smtp_code = extract_smtp_code(output)
      should_add_to_bounce = !NON_BOUNCE_CATEGORIES.include?(category.to_s)
      should_stop_mailing = STOP_MAILING_CATEGORIES.include?(category.to_s)
      
      {
        category: category,
        bounce_type: 'hard',
        smtp_code: smtp_code,
        message: output.presence || details.presence || status,
        should_add_to_bounce: should_add_to_bounce,
        should_stop_mailing: should_stop_mailing
      }
    end

    private

    def extract_text(payload, key)
      payload.dig(key) || payload.dig(key.to_s) || payload[key] || payload[key.to_s]
    end

    def find_category(text)
      ERROR_PATTERNS.each do |category, patterns|
        return category if patterns.any? { |pattern| text.include?(pattern.downcase) }
      end
      :unknown
    end

    def extract_smtp_code(text)
      return nil if text.blank?
      
      # Ищем SMTP код в формате "550 5.1.1" или просто "550"
      match = text.match(/(\d{3})(?:\s+[\d.]+)?/)
      match ? match[1] : nil
    end
  end
end

