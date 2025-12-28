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
      'too many messages'
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
      '550 5.7.1'
    ],
    user_not_found: [
      'user unknown',
      'mailbox not found',
      'does not exist',
      '550 5.1.1',
      'no such user',
      'recipient not found',
      'invalid recipient'
    ],
    mailbox_full: [
      'mailbox full',
      'quota exceeded',
      'over quota',
      '552',
      'mailbox is full',
      'storage quota'
    ],
    temporary: [
      'try again',
      'temporarily',
      '4.7.',
      'greylisted',
      'temporary failure',
      'try later'
    ],
    authentication: [
      'authentication',
      'spf',
      'dkim',
      'dmarc',
      'authentication failed',
      '550 5.7.23'
    ],
    connection: [
      'connection refused',
      'timeout',
      'unreachable',
      'connection error',
      'network error',
      'connection reset'
    ]
  }.freeze

  def self.classify(payload)
    output = extract_text(payload, :output) || ''
    details = extract_text(payload, :details) || ''
    status = extract_text(payload, :status) || ''
    
    full_text = "#{status} #{output} #{details}".downcase
    
    category = find_category(full_text)
    smtp_code = extract_smtp_code(output)
    
    {
      category: category,
      smtp_code: smtp_code,
      message: output.presence || details.presence || status
    }
  end

  private

  def self.extract_text(payload, key)
    payload.dig(key) || payload.dig(key.to_s) || payload[key] || payload[key.to_s]
  end

  def self.find_category(text)
    ERROR_PATTERNS.each do |category, patterns|
      return category if patterns.any? { |pattern| text.include?(pattern.downcase) }
    end
    :unknown
  end

  def self.extract_smtp_code(text)
    return nil if text.blank?
    
    # Ищем SMTP код в формате "550 5.1.1" или просто "550"
    match = text.match(/(\d{3})(?:\s+[\d.]+)?/)
    match ? match[1] : nil
  end
end

