# frozen_string_literal: true

class SmtpCredential < ApplicationRecord
  require 'bcrypt'

  # Validations
  validates :username, presence: true, uniqueness: true,
            format: { with: /\A[a-zA-Z0-9_-]+\z/, message: 'only allows letters, numbers, hyphens and underscores' }
  validates :password_hash, presence: true
  validates :rate_limit, numericality: { greater_than: 0 }

  # Scopes
  scope :active, -> { where(active: true) }
  scope :recently_used, -> { where('last_used_at > ?', 24.hours.ago) }
  scope :unused, -> { where(last_used_at: nil) }

  # Generate new SMTP credentials
  def self.generate(description: nil, rate_limit: 100)
    username = "smtp_#{SecureRandom.hex(8)}"
    password = SecureRandom.alphanumeric(24)

    credential = create!(
      username: username,
      password_hash: BCrypt::Password.create(password),
      description: description,
      rate_limit: rate_limit,
      active: true
    )

    [credential, password]
  end

  # Verify password
  def verify_password(password)
    BCrypt::Password.new(password_hash) == password
  end
  alias authenticate verify_password

  # Update last used timestamp
  def mark_as_used!
    update_column(:last_used_at, Time.current)
  end

  # Activate/deactivate
  def activate!
    update!(active: true)
  end

  def deactivate!
    update!(active: false)
  end

  # Display name for UI
  def display_name
    description.presence || username
  end

  # Check if recently used
  def recently_used?
    last_used_at.present? && last_used_at > 24.hours.ago
  end

  # Usage statistics
  def usage_count
    # This would be calculated from email_logs if we track smtp_credential_id
    0 # Placeholder
  end
end
