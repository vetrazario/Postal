# frozen_string_literal: true

FactoryBot.define do
  factory :email_open do
    association :email_log
    campaign_id { email_log.campaign_id || "camp_#{SecureRandom.hex(8)}" }
    token { EmailOpen.generate_token }
    opened_at { Time.current }
  end
end
