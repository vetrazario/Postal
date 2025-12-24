class MessageIdGenerator
  # Generate Message-ID on Send Server (NOT from AMS!)
  # Format: <local_{hex12}@{send_server_domain}>
  def self.generate
    random_id = SecureRandom.hex(12) # 24 hex characters
    domain = ENV.fetch("DOMAIN", "send1.example.com")
    "<local_#{random_id}@#{domain}>"
  end
end





