require 'rails_helper'

RSpec.describe MessageIdGenerator do
  describe ".generate" do
    it "generates message ID with correct format" do
      ENV["DOMAIN"] = "send1.example.com"
      message_id = MessageIdGenerator.generate
      
      expect(message_id).to match(/^<local_[a-f0-9]{24}@send1\.example\.com>$/)
    end

    it "does not contain AMS domain" do
      ENV["DOMAIN"] = "send1.example.com"
      message_id = MessageIdGenerator.generate
      
      expect(message_id).not_to include("ams")
    end
  end
end





