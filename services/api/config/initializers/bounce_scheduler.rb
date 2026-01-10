# frozen_string_literal: true

# Инициализация планировщика для очистки bounce записей
# Запускается при старте приложения и далее работает в цикле раз в день

Rails.application.config.after_initialize do
  # Запускаем только в production и только если Sidekiq доступен
  if Rails.env.production? && defined?(Sidekiq)
    begin
      # Проверяем, что таблица bounced_emails существует
      if ActiveRecord::Base.connection.table_exists?('bounced_emails')
        # Запускаем BounceSchedulerJob через 1 минуту после старта приложения
        # Это даст время системе полностью инициализироваться
        BounceSchedulerJob.set(wait: 1.minute).perform_later

        Rails.logger.info "✓ BounceSchedulerJob initialized - will start in 1 minute"
      else
        Rails.logger.warn "⚠ BounceSchedulerJob NOT initialized - bounced_emails table does not exist"
      end
    rescue => e
      Rails.logger.error "✗ Failed to initialize BounceSchedulerJob: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end
  else
    Rails.logger.info "ℹ BounceSchedulerJob NOT initialized - only runs in production with Sidekiq"
  end
end
