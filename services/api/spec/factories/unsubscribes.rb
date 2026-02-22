# frozen_string_literal: true

FactoryBot.define do
  factory :unsubscribe do
    email { 'user@example.com' }
    campaign_id { nil }
    reason { 'user_request' }
    unsubscribed_at { Time.current }

    trait :with_campaign do
      campaign_id { "campaign_#{SecureRandom.hex(8)}" }
    end
  end
end
