# frozen_string_literal: true

class CleanupOldBouncesJob < ApplicationJob
  queue_as :low

  BOUNCE_RETENTION_DAYS = 90 # Хранить bounce записи 90 дней

  def perform
    cutoff_date = BOUNCE_RETENTION_DAYS.days.ago

    # Удалить старые записи bounce
    deleted_bounces = BouncedEmail.where('last_bounced_at < ?', cutoff_date).delete_all

    # Удалить старые записи unsubscribe (если есть соответствующая миграция)
    deleted_unsubscribes = Unsubscribe.where('unsubscribed_at < ?', cutoff_date).delete_all

    # Удалить старые записи delivery errors (они нужны только для анализа последних 90 дней)
    deleted_errors = DeliveryError.where('created_at < ?', cutoff_date).delete_all

    Rails.logger.info "CleanupOldBouncesJob: Deleted #{deleted_bounces} bounce records, #{deleted_unsubscribes} unsubscribe records, and #{deleted_errors} delivery errors older than #{BOUNCE_RETENTION_DAYS} days"

    {
      deleted_bounces: deleted_bounces,
      deleted_unsubscribes: deleted_unsubscribes,
      deleted_errors: deleted_errors,
      cutoff_date: cutoff_date
    }
  rescue StandardError => e
    Rails.logger.error "CleanupOldBouncesJob error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end
end


