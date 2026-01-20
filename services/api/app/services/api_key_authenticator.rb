class ApiKeyAuthenticator
  def self.call(token)
    return nil if token.blank?
    
    key_hash = Digest::SHA256.hexdigest(token)
    api_key = ApiKey.find_by(key_hash: key_hash, active: true)
    
    if api_key
      api_key.touch_last_used
      api_key
    else
      nil
    end
  end
end





