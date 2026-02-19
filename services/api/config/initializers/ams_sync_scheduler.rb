# frozen_string_literal: true

# Initialize AMS Open/Clicks sync job
# Periodically sends batched open/click data to AMS via postMailingOpenClicksData API
# Self-scheduling: runs every 30 seconds

Rails.application.config.after_initialize do
  if Rails.env.production? && defined?(Sidekiq)
    begin
      AmsOpenClicksSyncJob.set(wait: 30.seconds).perform_later
      Rails.logger.info "AmsOpenClicksSyncJob initialized - will start in 30 seconds"
    rescue => e
      Rails.logger.error "Failed to initialize AmsOpenClicksSyncJob: #{e.message}"
    end
  end
end
