#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage: from API root: bundle exec rails runner scripts/diagnose_campaign_opens.rb [CAMPAIGN_ID]
# Purpose: Diagnose why opens are missing in analytics for a campaign (EmailOpen + TrackingEvent).

campaign_id = ARGV[0] || ENV['CAMPAIGN_ID']
unless campaign_id.present?
  puts "Usage: rails runner scripts/diagnose_campaign_opens.rb <CAMPAIGN_ID>"
  puts "   or: CAMPAIGN_ID=xxx rails runner scripts/diagnose_campaign_opens.rb"
  exit 1
end

puts "=== Diagnosing campaign opens for: #{campaign_id} ===\n"

logs = EmailLog.where(campaign_id: campaign_id).order(created_at: :desc).limit(500)
total = logs.count
delivered = logs.where(status: 'delivered').count

puts "EmailLog: total=#{total}, delivered=#{delivered}"

if total.zero?
  puts "No email logs for this campaign. Exiting."
  exit 0
end

sample = logs.limit(5)
missing_ext = logs.where(external_message_id: [nil, ''])
missing_ext_count = missing_ext.count
log_ids = logs.pluck(:id)

opens_email_open = EmailOpen.where(email_log_id: log_ids).count
opens_tracking   = TrackingEvent.where(email_log_id: log_ids, event_type: 'open').count
total_opens      = opens_email_open + opens_tracking

puts "Opens: EmailOpen=#{opens_email_open}, TrackingEvent(open)=#{opens_tracking}, total=#{total_opens}"
puts "Logs missing external_message_id: #{missing_ext_count}"

if missing_ext_count > 0
  puts "\n  -> Tracking pixel uses external_message_id or message_id; if external_message_id is nil, message_id is used (BuildEmailJob fallback)."
  puts "  -> Sample log without external_message_id: message_id=#{missing_ext.limit(1).pluck(:message_id).first}"
end

if delivered > 0 && total_opens.zero?
  puts "\nPossible causes:"
  puts "  1. Recipients have not opened yet, or opens are from bots (filtered by TrackingHandler)."
  puts "  2. Pixel URL or tracking domain not reachable (check tracking service and domain)."
  puts "  3. message_id in pixel not found by TrackingHandler (search is by external_message_id OR message_id)."
  puts "  4. EmailOpen records created by other path (e.g. webhook) not yet present."
end

puts "\nSample email_logs (first 3):"
logs.limit(3).each do |log|
  puts "  id=#{log.id} message_id=#{log.message_id} external_message_id=#{log.external_message_id.inspect} status=#{log.status}"
end

puts "\nDone."
