# Cryptographic signing and verification for Postal webhooks
module EncryptoSigno
  class << self
    def sign(private_key, data)
      signature = private_key.sign(OpenSSL::Digest::SHA256.new, data)
      Base64.strict_encode64(signature)
    end

    def verify(public_key, signature, data)
      decoded = Base64.decode64(signature)
      public_key.verify(OpenSSL::Digest::SHA256.new, decoded, data)
    rescue OpenSSL::PKey::RSAError, ArgumentError
      false
    end
  end
end
