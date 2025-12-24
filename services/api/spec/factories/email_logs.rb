FactoryBot.define do
  factory :email_log do
    message_id { "local_#{SecureRandom.hex(12)}" }
    external_message_id { "msg_#{SecureRandom.hex(8)}" }
    campaign_id { "camp_#{SecureRandom.hex(8)}" }
    recipient { "user@example.com" }
    recipient_masked { "u***@example.com" }
    sender { "sender@example.com" }
    subject { "Test Subject" }
    status { "queued" }
  end
end





