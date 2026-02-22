# frozen_string_literal: true

require 'webmock/rspec'

WebMock.disable_net_connect!(allow_localhost: true)

RSpec.configure do |config|
  config.before(:each) do
    # Allow connections to test database, Redis
    WebMock.disable_net_connect!(allow_localhost: true)
  end
end
