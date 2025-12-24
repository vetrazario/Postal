require 'rails_helper'

RSpec.describe ApiKey, type: :model do
  describe "generation" do
    it "generates key with hash" do
      api_key, raw_key = ApiKey.generate(name: "Test Key")
      
      expect(api_key).to be_persisted
      expect(raw_key).to be_present
      expect(raw_key.length).to eq(48) # 24 bytes = 48 hex chars
      expect(api_key.key_hash).to eq(Digest::SHA256.hexdigest(raw_key))
    end
  end

  describe "authentication" do
    it "hashes key correctly" do
      api_key, raw_key = ApiKey.generate(name: "Test")
      expect(ApiKeyAuthenticator.call(raw_key)).to eq(api_key)
    end
  end
end





