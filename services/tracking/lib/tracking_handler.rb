require 'pg'
require 'base64'
require 'json'
require 'active_support/core_ext/object/blank'

class TrackingHandler
  def initialize(database_url:, redis_url:)
    @database_url = database_url
    @redis_url = redis_url
  end

  def handle_open(eid:, cid:, mid:, ip:, user_agent:)
    return { success: false } if eid.blank? || cid.blank? || mid.blank?
    
    # Decode parameters
    email = Base64.urlsafe_decode64(eid) rescue nil
    campaign_id = Base64.urlsafe_decode64(cid) rescue nil
    message_id = Base64.urlsafe_decode64(mid) rescue nil
    
    return { success: false } unless email && campaign_id && message_id
    
    # Find email log
    conn = nil
    begin
      conn = PG.connect(@database_url)
      result = conn.exec_params(
        "SELECT id, external_message_id, campaign_id FROM email_logs WHERE external_message_id = $1",
        [message_id]
      )
      
      return { success: false } if result.rows.empty?
      
      email_log_id = result.rows.first[0]
      
      # Create tracking event (don't store decrypted email for PII protection)
      conn.exec_params(
        "INSERT INTO tracking_events (email_log_id, event_type, event_data, ip_address, user_agent, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, NOW(), NOW())",
        [email_log_id, 'open', { campaign_id: campaign_id }.to_json, ip, user_agent]
      )
      
      # Enqueue webhook job
      enqueue_webhook_job(message_id, 'opened', { ip: ip, user_agent: user_agent })
      
      { success: true }
    rescue => e
      puts "TrackingHandler error: #{e.message}"
      { success: false }
    ensure
      conn&.close
    end
  end

  def handle_click(url:, eid:, cid:, mid:, ip:, user_agent:)
    return { success: false, url: nil } if url.blank? || eid.blank? || cid.blank? || mid.blank?
    
    # Decode parameters
    original_url = Base64.urlsafe_decode64(url) rescue nil
    email = Base64.urlsafe_decode64(eid) rescue nil
    campaign_id = Base64.urlsafe_decode64(cid) rescue nil
    message_id = Base64.urlsafe_decode64(mid) rescue nil
    
    return { success: false, url: nil } unless original_url && email && campaign_id && message_id
    
    # Find email log
    conn = nil
    begin
      conn = PG.connect(@database_url)
      result = conn.exec_params(
        "SELECT id, external_message_id, campaign_id FROM email_logs WHERE external_message_id = $1",
        [message_id]
      )
      
      return { success: false, url: nil } if result.rows.empty?
      
      email_log_id = result.rows.first[0]
      
      # Create tracking event (don't store decrypted email for PII protection)
      conn.exec_params(
        "INSERT INTO tracking_events (email_log_id, event_type, event_data, ip_address, user_agent, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, NOW(), NOW())",
        [email_log_id, 'click', { url: original_url, campaign_id: campaign_id }.to_json, ip, user_agent]
      )
      
      # Enqueue webhook job
      enqueue_webhook_job(message_id, 'clicked', { url: original_url, ip: ip, user_agent: user_agent })
      
      { success: true, url: original_url }
    rescue => e
      puts "TrackingHandler error: #{e.message}"
      { success: false, url: nil }
    ensure
      conn&.close
    end
  end

  def handle_unsubscribe(eid:, cid:, ip:, user_agent:)
    return { success: false } if eid.blank?

    # Decode parameters
    email = Base64.urlsafe_decode64(eid) rescue nil
    campaign_id = cid.present? ? (Base64.urlsafe_decode64(cid) rescue nil) : nil

    return { success: false } unless email

    # Mask email for display (e.g., t***@example.com)
    email_masked = mask_email(email)

    conn = nil
    begin
      conn = PG.connect(@database_url)

      # Find email logs for this recipient (optionally filtered by campaign)
      query = if campaign_id
                "SELECT id, external_message_id FROM email_logs WHERE recipient = $1 AND campaign_id = $2 ORDER BY created_at DESC LIMIT 1"
              else
                "SELECT id, external_message_id FROM email_logs WHERE recipient = $1 ORDER BY created_at DESC LIMIT 1"
              end

      params = campaign_id ? [email, campaign_id] : [email]
      result = conn.exec_params(query, params)

      email_log_id = result.rows.first&.[](0)
      message_id = result.rows.first&.[](1)

      # Create unsubscribe tracking event
      if email_log_id
        conn.exec_params(
          "INSERT INTO tracking_events (email_log_id, event_type, event_data, ip_address, user_agent, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, NOW(), NOW())",
          [email_log_id, 'unsubscribe', { campaign_id: campaign_id, email_masked: email_masked }.to_json, ip, user_agent]
        )
      end

      # Enqueue webhook job for unsubscribe notification
      enqueue_webhook_job(message_id || 'unknown', 'unsubscribed', {
        email_masked: email_masked,
        campaign_id: campaign_id,
        ip: ip,
        user_agent: user_agent
      })

      { success: true, email_masked: email_masked }
    rescue => e
      puts "TrackingHandler unsubscribe error: #{e.message}"
      { success: false }
    ensure
      conn&.close
    end
  end

  private

  def mask_email(email)
    return email unless email.include?('@')
    local, domain = email.split('@')
    masked_local = local.length > 2 ? "#{local[0]}***#{local[-1]}" : "#{local[0]}***"
    "#{masked_local}@#{domain}"
  end

  def enqueue_webhook_job(message_id, event_type, data)
    # Use Sidekiq to enqueue job
    require 'sidekiq'
    Sidekiq.configure_client do |config|
      config.redis = { url: @redis_url }
    end
    
    # This will be handled by ReportToAmsJob in the API service
    # For now, we'll just log it
    puts "Webhook: #{event_type} for #{message_id}"
  end
end





