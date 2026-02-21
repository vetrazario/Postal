# frozen_string_literal: true

FactoryBot.define do
  factory :tracking_event do
    association :email_log
    event_type { 'open' }
    event_data { {} }

    trait :click do
      event_type { 'click' }
      event_data { { url: 'https://example.com', campaign_id: email_log.campaign_id } }
    end
  end
end
