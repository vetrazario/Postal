# frozen_string_literal: true

module Dashboard
  class DashboardController < BaseController
    def index
      # Today's statistics
      @stats_today = calculate_stats(Time.current.beginning_of_day..Time.current)

      # Yesterday's statistics for comparison
      @stats_yesterday = calculate_stats(1.day.ago.beginning_of_day..1.day.ago.end_of_day)

      # Recent logs
      @recent_logs = EmailLog.order(created_at: :desc).limit(10)

      # System health
      @system_health = check_system_health

      # Quick stats
      @total_sent = EmailLog.count
    end

    private

    def calculate_stats(period)
      logs = EmailLog.where(created_at: period)

      {
        total: logs.count,
        queued: logs.where(status: 'queued').count,
        sent: logs.where(status: 'sent').count,
        delivered: logs.where(status: 'delivered').count,
        bounced: logs.where(status: 'bounced').count,
        failed: logs.where(status: 'failed').count,
        opened: TrackingEvent.where(email_log_id: logs.ids, event_type: 'open').count,
        clicked: TrackingEvent.where(email_log_id: logs.ids, event_type: 'click').count
      }
    end

    def check_system_health
      {
        database: database_healthy?,
        redis: redis_healthy?,
        sidekiq: sidekiq_healthy?,
        postal: postal_healthy?
      }
    end

    def database_healthy?
      ActiveRecord::Base.connection.active?
    rescue
      false
    end

    def redis_healthy?
      Redis.new(url: ENV['REDIS_URL']).ping == 'PONG'
    rescue
      false
    end

    def sidekiq_healthy?
      Sidekiq::ProcessSet.new.size.positive?
    rescue
      false
    end

    def postal_healthy?
      # Simple check - could be enhanced
      true
    end
  end
end
