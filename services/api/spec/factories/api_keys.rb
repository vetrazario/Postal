FactoryBot.define do
  factory :api_key do
    name { "Test API Key" }
    key_hash { Digest::SHA256.hexdigest(SecureRandom.hex(24)) }
    permissions { { send: true, batch: true } }
    rate_limit { 100 }
    daily_limit { 0 }
    active { true }
    
    trait :with_raw_key do
      after(:build) do |api_key|
        raw_key = SecureRandom.hex(24)
        api_key.key_hash = Digest::SHA256.hexdigest(raw_key)
        api_key.raw_key = raw_key
      end
    end
  end
end





