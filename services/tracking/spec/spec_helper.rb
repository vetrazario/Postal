# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

ENV['RACK_ENV'] = 'test'

require 'rack/test'
require_relative '../app'

RSpec.configure do |config|
  config.include Rack::Test::Methods
end

def app
  TrackingApp
end
