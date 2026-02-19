# frozen_string_literal: true

class AmsOpenClicksSyncJob < ApplicationJob
  queue_as :low

  MAX_BATCH_SIZE = 20_000
  SYNC_INTERVAL = 30.seconds
  REDIS_KEY_PATTERN = 'ams_open_clicks:*'

  def perform
    unless ams_configured?
      Rails.logger.debug "AmsOpenClicksSyncJob: AMS not configured, skipping"
      return
    end

    client = build_ams_client
    redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://redis:6379/0'))

    keys = redis.keys(REDIS_KEY_PATTERN)

    keys.each do |key|
      campaign_id = key.sub('ams_open_clicks:', '')
      flush_campaign(redis, client, campaign_id, key)
    end

    redis.close
  rescue StandardError => e
    Rails.logger.error "AmsOpenClicksSyncJob error: #{e.message}"
  ensure
    # Re-schedule (self-scheduling pattern, same as BounceSchedulerJob)
    self.class.set(wait: SYNC_INTERVAL).perform_later
  end

  private

  def flush_campaign(redis, client, campaign_id, key)
    items = []
    while items.size < MAX_BATCH_SIZE
      raw = redis.rpop(key)
      break unless raw

      parsed = JSON.parse(raw)
      items << parsed
    end

    return if items.empty?

    client.post_open_clicks_data(campaign_id, items)
    Rails.logger.info "AmsOpenClicksSyncJob: sent #{items.size} events for campaign #{campaign_id}"
  rescue AmsClient::AmsError => e
    # Push items back to Redis for retry
    items.reverse_each { |item| redis.rpush(key, item.to_json) }
    Rails.logger.error "AmsOpenClicksSyncJob: AMS error for campaign #{campaign_id}: #{e.message}"
  rescue StandardError => e
    items.reverse_each { |item| redis.rpush(key, item.to_json) }
    Rails.logger.error "AmsOpenClicksSyncJob: error for campaign #{campaign_id}: #{e.message}"
  end

  def ams_configured?
    SystemConfig.get(:ams_api_url).present? && SystemConfig.get(:ams_api_key).present?
  end

  def build_ams_client
    AmsClient.new(
      api_url: SystemConfig.get(:ams_api_url),
      api_key: SystemConfig.get(:ams_api_key)
    )
  end
end
