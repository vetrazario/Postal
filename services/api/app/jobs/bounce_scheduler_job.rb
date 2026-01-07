# frozen_string_literal: true

class BounceSchedulerJob < ApplicationJob
  queue_as :low

  def perform
    # Очистить старые bounce записи
    CleanupOldBouncesJob.perform_later
    
    Rails.logger.info "BounceSchedulerJob: Scheduled cleanup for old bounce records"
    
    # Перезапустить планировщик (выполнять раз в день)
    BounceSchedulerJob.set(wait: 1.day).perform_later
  rescue => e
    Rails.logger.error "BounceSchedulerJob error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    
    # Попробовать перезапустить через час при ошибке
    BounceSchedulerJob.set(wait: 1.hour).perform_later
  end
end


