# frozen_string_literal: true

# Helper class to mask email addresses for privacy protection
# Used in logs and responses to avoid exposing full email addresses
class EmailMasker
  # Mask email address for display
  # john.doe@example.com -> j***e@example.com
  # ab@example.com -> a***@example.com
  def self.mask_email(email)
    return '***@***.***' if email.blank?
    return email unless email.include?('@')

    local, domain = email.split('@', 2)

    masked_local = if local.length <= 2
      "#{local[0]}***"
    else
      "#{local[0]}***#{local[-1]}"
    end

    "#{masked_local}@#{domain}"
  rescue StandardError
    '***@***.***'
  end

  # Mask multiple emails
  def self.mask_emails(emails)
    return [] if emails.blank?

    Array(emails).map { |email| mask_email(email) }
  end
end
