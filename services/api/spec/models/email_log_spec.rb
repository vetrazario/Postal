require 'rails_helper'

RSpec.describe EmailLog, type: :model do
  describe "masking" do
    it "masks email correctly" do
      masked = EmailLog.mask_email("user@example.com")
      expect(masked).to eq("u***r@example.com")
    end

    it "masks short email correctly" do
      masked = EmailLog.mask_email("ab@example.com")
      expect(masked).to eq("a***@example.com")
    end
  end

  describe "status updates" do
    let(:email_log) { create(:email_log) }

    it "updates status correctly" do
      email_log.update_status('sent')
      expect(email_log.status).to eq('sent')
      expect(email_log.sent_at).to be_present
    end
  end
end





