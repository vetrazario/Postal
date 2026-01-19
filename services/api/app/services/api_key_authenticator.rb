class ApiKeyAuthenticator
  def self.call(token)
    return nil if token.blank?
    
    # Используем соль для хеширования API ключей (защита от rainbow table атак)
    salt = ENV.fetch('API_KEY_SALT') { SecureRandom.hex(32) }
    key_hash = Digest::SHA256.hexdigest("#{salt}#{token}")
    api_key = ApiKey.find_by(key_hash: key_hash, active: true)
    
    if api_key
      api_key.touch_last_used
      api_key
    else
      nil
    end
  end
end





