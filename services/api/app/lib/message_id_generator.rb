class MessageIdGenerator
  # Generate Message-ID (MTA-like format, avoids SpamAssassin MSGID_RANDY)
  # Format: <timestamp_base36.random_alphanumeric@domain>
  def self.generate
    timestamp = Time.current.to_i.to_s(36)
    random = SecureRandom.alphanumeric(24)
    domain = SystemConfig.get(:domain) || "mail.example.com"
    "<#{timestamp}.#{random}@#{domain}>"
  end
end





