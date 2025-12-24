require_relative 'config/environment'
api_key, raw_key = ApiKey.generate(name: 'Test Key', active: true)
puts "API Key: #{raw_key}"
puts "Save this key - it will not be shown again!"

