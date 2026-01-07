# frozen_string_literal: true

FactoryBot.define do
  factory :bounced_email do
    email { "user@example.com" }
    bounce_type { "hard" }
    bounce_category { "user_not_found" }
    smtp_code { "550" }
    smtp_message { "The email account does not exist" }
    campaign_id { nil }
    bounce_count { 1 }
    first_bounced_at { Time.current }
    last_bounced_at { Time.current }

    trait :with_campaign do
      campaign_id { "campaign_#{SecureRandom.hex(8)}" }
    end

    trait :spam_block do
      bounce_category { "spam_block" }
      smtp_code { "550" }
      smtp_message { "Message has been blocked" }
    end

    trait :mailbox_full do
      bounce_category { "mailbox_full" }
      smtp_code { "550" }
      smtp_message { "Mailbox is full" }
    end

    trait :rate_limit do
      bounce_category { "rate_limit" }
      smtp_code { "421" }
      smtp_message { "Rate limit exceeded" }
    end

    trait :temporary do
      bounce_category { "temporary" }
      smtp_code { "421" }
      smtp_message { "Temporary failure" }
    end
  end
end


