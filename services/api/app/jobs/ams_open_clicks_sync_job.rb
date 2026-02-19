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
    # Set: SMEMBERS возвращает уникальные элементы (дедупликация по email+url уже сделана при записи)
    members = redis.smembers(key)
    return if members.empty?

    raw_batch = members.first(MAX_BATCH_SIZE)
    parsed = raw_batch.map { |raw| JSON.parse(raw) }
    client.post_open_clicks_data(campaign_id, parsed)
    redis.srem(key, *raw_batch)
    Rails.logger.info "AmsOpenClicksSyncJob: sent #{parsed.size} unique events for campaign #{campaign_id}"
  rescue AmsClient::AmsError => e
    # Не удаляем — останутся в Set для повторной попытки
    Rails.logger.error "AmsOpenClicksSyncJob: AMS error for campaign #{campaign_id}: #{e.message}"
  rescue StandardError => e
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
