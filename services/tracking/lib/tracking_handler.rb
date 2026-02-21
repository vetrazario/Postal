require 'pg'
require 'base64'
require 'json'
require 'uri'
require 'openssl'
require 'active_support/core_ext/object/blank'

class TrackingHandler
  # Allowed URL schemes for redirect
  ALLOWED_SCHEMES = %w[http https].freeze

  # Blocked domains (known phishing/malicious)
  BLOCKED_DOMAINS = %w[
    bit.ly
    tinyurl.com
  ].freeze

  BOT_PATTERNS = [
    /\bbot\b/, /\bcrawl/, /\bspider/, /\bslurp\b/, /mediapartners/, /facebookexternalhit/,
    /twitterbot/, /whatsapp/, /googlebot/, /bingbot/, /yandexbot/, /\bscanner\b/, /\bpreview\b.*\bbot/
  ].freeze

  def initialize(database_url:, redis_url:, allowed_domains: nil)
    @database_url = database_url
    @redis_url = redis_url
    @allowed_domains = allowed_domains # Optional whitelist
  end

  def handle_open(eid:, cid:, mid:, ip:, user_agent:)
    return { success: false } if eid.blank? || cid.blank? || mid.blank?
    
    # Decode parameters
    email = Base64.urlsafe_decode64(eid) rescue nil
    campaign_id = Base64.urlsafe_decode64(cid) rescue nil
    message_id = Base64.urlsafe_decode64(mid) rescue nil
    
    return { success: false } unless email && campaign_id && message_id

    # Пропускаем ботов (возвращаем success чтобы отдать пиксель, но не пишем в БД)
    return { success: true } if bot_request?(user_agent)
    
    # Find email log
    conn = nil
    begin
      conn = PG.connect(@database_url)
      result = conn.exec_params(
        "SELECT id, external_message_id, campaign_id FROM email_logs WHERE external_message_id = $1 OR message_id = $1 LIMIT 1",
        [message_id]
      )
      
      return { success: false } if result.ntuples == 0
      
      email_log_id = result[0]['id']

      # Только первое открытие на письмо — повторные загрузки пикселя не считаем
      existing = conn.exec_params(
        "SELECT 1 FROM tracking_events WHERE email_log_id = $1 AND event_type = 'open' LIMIT 1",
        [email_log_id]
      )
      return { success: true } if existing.ntuples > 0
      
      # Create tracking event (don't store decrypted email for PII protection)
      conn.exec_params(
        "INSERT INTO tracking_events (email_log_id, event_type, event_data, ip_address, user_agent, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, NOW(), NOW())",
        [email_log_id, 'open', { campaign_id: campaign_id }.to_json, ip, user_agent]
      )
      
      # Buffer for AMS postMailingOpenClicksData
      push_to_ams_buffer(campaign_id, email, 'open_trace')

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

    # SECURITY: Validate URL to prevent open redirect attacks
    validated_url = validate_redirect_url(original_url)
    if validated_url.nil?
      puts "TrackingHandler: Blocked suspicious URL redirect: #{original_url[0..100]}"
      return { success: false, url: nil, error: 'Invalid redirect URL' }
    end

    # Find email log
    conn = nil
    begin
      conn = PG.connect(@database_url)
      result = conn.exec_params(
        "SELECT id, external_message_id, campaign_id FROM email_logs WHERE external_message_id = $1 OR message_id = $1 LIMIT 1",
        [message_id]
      )

      return { success: false, url: nil } if result.ntuples == 0

      email_log_id = result[0]['id']

      # Create tracking event (don't store decrypted email for PII protection)
      conn.exec_params(
        "INSERT INTO tracking_events (email_log_id, event_type, event_data, ip_address, user_agent, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, NOW(), NOW())",
        [email_log_id, 'click', { url: validated_url, campaign_id: campaign_id }.to_json, ip, user_agent]
      )

      # Buffer for AMS postMailingOpenClicksData
      push_to_ams_buffer(campaign_id, email, validated_url)

      # Enqueue webhook job
      enqueue_webhook_job(message_id, 'clicked', { url: validated_url, ip: ip, user_agent: user_agent })

      { success: true, url: validated_url }
    rescue => e
      puts "TrackingHandler error: #{e.message}"
      { success: false, url: nil }
    ensure
      conn&.close
    end
  end

  def handle_unsubscribe(eid:, cid:, mid: nil, ip:, user_agent:, reason: 'user_request')
    return { success: false, error: 'Missing parameters' } if eid.blank? || cid.blank?

    # Decode parameters
    email = Base64.urlsafe_decode64(eid) rescue nil
    campaign_id = Base64.urlsafe_decode64(cid) rescue nil
    message_id = mid.present? ? (Base64.urlsafe_decode64(mid) rescue nil) : nil

    return { success: false, error: 'Invalid parameters' } unless email && campaign_id

    conn = nil
    begin
      conn = PG.connect(@database_url)

      # Insert into unsubscribes table (upsert - update timestamp if exists)
      conn.exec_params(
        <<~SQL,
          INSERT INTO unsubscribes (email, campaign_id, reason, ip_address, user_agent, unsubscribed_at, created_at, updated_at)
          VALUES ($1, $2, $3, $4, $5, NOW(), NOW(), NOW())
          ON CONFLICT (email, campaign_id) DO UPDATE SET
            unsubscribed_at = NOW(),
            updated_at = NOW(),
            reason = EXCLUDED.reason
        SQL
        [email, campaign_id, reason, ip, user_agent]
      )

      # Global unsubscribe (campaign_id = NULL) — одна запись на email для блокировки по всем кампаниям
      conn.exec_params(
        <<~SQL,
          INSERT INTO unsubscribes (email, campaign_id, reason, ip_address, user_agent, unsubscribed_at, created_at, updated_at)
          SELECT $1, NULL, $2, $3, $4, NOW(), NOW(), NOW()
          WHERE NOT EXISTS (SELECT 1 FROM unsubscribes WHERE email = $1 AND campaign_id IS NULL)
        SQL
        [email, reason, ip, user_agent]
      )

      # If we have message_id, also create tracking event
      if message_id.present?
        result = conn.exec_params(
          "SELECT id FROM email_logs WHERE external_message_id = $1",
          [message_id]
        )

        if result.ntuples > 0
          email_log_id = result[0]['id']
          conn.exec_params(
            "INSERT INTO tracking_events (email_log_id, event_type, event_data, ip_address, user_agent, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, NOW(), NOW())",
            [email_log_id, 'unsubscribe', { campaign_id: campaign_id, reason: reason }.to_json, ip, user_agent]
          )
        end
      end

      # Buffer for AMS postMailingOpenClicksData
      push_to_ams_buffer(campaign_id, email, 'Unsubscribe_Click:DC,AE{|;')

      # Enqueue webhook job to notify AMS
      enqueue_webhook_job(message_id || "unsub_#{campaign_id}", 'unsubscribed', {
        email_masked: mask_email(email),
        campaign_id: campaign_id,
        reason: reason,
        ip: ip
      })

      { success: true, email_masked: mask_email(email) }
    rescue => e
      puts "TrackingHandler unsubscribe error: #{e.message}"
      { success: false, error: 'Database error' }
    ensure
      conn&.close
    end
  end

  private

  def bot_request?(user_agent)
    ua = (user_agent || '').to_s.downcase
    BOT_PATTERNS.any? { |pattern| ua.match?(pattern) }
  end

  # Mask email for display (privacy protection)
  def mask_email(email)
    return '***' if email.blank?
    return email unless email.include?('@')

    local, domain = email.split('@', 2)
    if local.length <= 2
      "#{local[0]}***@#{domain}"
    else
      "#{local[0]}***#{local[-1]}@#{domain}"
    end
  end

  # Validate URL to prevent open redirect attacks
  def validate_redirect_url(url)
    return nil if url.blank?

    begin
      uri = URI.parse(url)

      # Check scheme is allowed (http/https only)
      return nil unless ALLOWED_SCHEMES.include?(uri.scheme&.downcase)

      # Check host is present
      return nil if uri.host.blank?

      # Block javascript: and data: URLs that might slip through
      return nil if url.downcase.start_with?('javascript:', 'data:', 'vbscript:')

      # Check against blocked domains
      host_downcase = uri.host.downcase
      return nil if BLOCKED_DOMAINS.any? { |blocked| host_downcase.end_with?(blocked) }

      # If whitelist is configured, check against it
      if @allowed_domains.present?
        domain_allowed = @allowed_domains.any? do |allowed|
          host_downcase == allowed.downcase || host_downcase.end_with?(".#{allowed.downcase}")
        end
        return nil unless domain_allowed
      end

      # Block local/internal IPs
      return nil if local_ip?(uri.host)

      # URL is safe to redirect to
      url
    rescue URI::InvalidURIError
      nil
    end
  end

  def local_ip?(host)
    return true if host == 'localhost'
    return true if host.start_with?('127.')
    return true if host.start_with?('10.')
    return true if host.start_with?('192.168.')
    return true if host =~ /^172\.(1[6-9]|2[0-9]|3[0-1])\./
    return true if host == '0.0.0.0'
    return true if host == '::1'
    false
  end

  def push_to_ams_buffer(campaign_id, email, url)
    return if campaign_id.blank? || email.blank?

    redis = Redis.new(url: @redis_url)
    # Set вместо List — уникальность по (email, url), повторные открытия/клики не дублируются
    redis.sadd("ams_open_clicks:#{campaign_id}", { email: email, url: url }.to_json)
    redis.expire("ams_open_clicks:#{campaign_id}", 86400)
  rescue => e
    puts "AMS buffer push error: #{e.message}"
  ensure
    redis&.close
  end

  def enqueue_webhook_job(message_id, event_type, data)
    # Send webhook via HTTP request to API service
    require 'net/http'
    require 'json'

    api_url = ENV['API_URL'] || 'http://api:3000'
    webhook_secret = ENV['WEBHOOK_SECRET']

    begin
      uri = URI("#{api_url}/api/v1/internal/tracking_event")
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 5
      http.read_timeout = 10

      request = Net::HTTP::Post.new(uri.path)
      request['Content-Type'] = 'application/json'

      payload = {
        message_id: message_id,
        event_type: event_type,
        data: data,
        timestamp: Time.now.to_i
      }

      # Add HMAC signature if secret is configured
      if webhook_secret.present?
        signature = OpenSSL::HMAC.hexdigest('SHA256', webhook_secret, payload.to_json)
        request['X-Tracking-Signature'] = signature
      end

      request.body = payload.to_json
      response = http.request(request)

      puts "Webhook sent: #{event_type} for #{message_id} - #{response.code}"
    rescue => e
      puts "Webhook error: #{e.message}"
    end
  end
end





