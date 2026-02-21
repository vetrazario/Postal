# frozen_string_literal: true

FactoryBot.define do
  factory :email_click do
    association :email_log
    campaign_id { email_log.campaign_id || "camp_#{SecureRandom.hex(8)}" }
    url { "https://example.com/link" }
    token { EmailClick.generate_token }
    clicked_at { Time.current }
  end
end
