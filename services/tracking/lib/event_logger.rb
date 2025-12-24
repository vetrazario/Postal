# EventLogger - placeholder for future logging enhancements

class EventLogger
  def self.log(event_type, data)
    puts "[#{Time.now.iso8601}] #{event_type}: #{data.to_json}"
  end
end





