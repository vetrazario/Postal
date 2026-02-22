require 'rails_helper'

RSpec.describe MessageIdGenerator do
  before { allow(SystemConfig).to receive(:get).with(:domain).and_return('send1.example.com') }

  describe ".generate" do
    it "generates message ID with correct format" do
      message_id = MessageIdGenerator.generate
      
      expect(message_id).to match(/^<[a-z0-9]+\.[a-zA-Z0-9]{24}@send1\.example\.com>$/)
    end

    it "does not contain AMS domain" do
      message_id = MessageIdGenerator.generate
      
      expect(message_id).not_to include("ams")
    end
  end
end





