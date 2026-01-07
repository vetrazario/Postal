require 'httparty'

module Api
  module V1
    class HealthController < ActionController::API
      def show
        checks = {
          database: check_database,
          redis: check_redis,
          postal: check_postal,
          sidekiq: check_sidekiq,
          bounce_tables: check_bounce_tables
        }
        
        # Критические проверки (без них API не может работать)
        critical_checks = [:database, :redis, :sidekiq, :bounce_tables]
        critical_healthy = critical_checks.all? { |key| checks[key][:status] == 'ok' }
        
        # Postal не критичен - может быть недоступен временно
        all_healthy = checks.values.all? { |c| c[:status] == 'ok' }

        render json: {
          status: critical_healthy ? (all_healthy ? 'healthy' : 'degraded') : 'unhealthy',
          timestamp: Time.current.iso8601,
          checks: checks
        }, status: critical_healthy ? :ok : :service_unavailable
      end

      private

      def check_database
        ActiveRecord::Base.connection.execute('SELECT 1')
        { status: 'ok' }
      rescue StandardError => e
        { status: 'error', message: e.message }
      end

      def check_redis
        redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
        redis.ping
        { status: 'ok' }
      rescue StandardError => e
        { status: 'error', message: e.message }
      ensure
        redis&.close
      end

      def check_postal
        postal_url = ENV.fetch('POSTAL_API_URL', 'http://postal:5000')
        response = HTTParty.get("#{postal_url}/api/v1/health", timeout: 5)
        if response.success? && response.code == 200
          { status: 'ok' }
        else
          { status: 'error', message: 'Postal not accessible' }
        end
      rescue StandardError => e
        { status: 'error', message: e.message }
      end

      def check_sidekiq
        # Проверка что Sidekiq может подключиться к Redis
        Sidekiq.redis { |conn| conn.ping == 'PONG' }
        { status: 'ok' }
      rescue StandardError => e
        { status: 'error', message: e.message }
      end

      def check_bounce_tables
        # Проверка что таблицы bounce существуют
        bounced_exists = ActiveRecord::Base.connection.table_exists?('bounced_emails')
        unsubscribes_exists = ActiveRecord::Base.connection.table_exists?('unsubscribes')
        
        if bounced_exists && unsubscribes_exists
          { status: 'ok' }
        else
          { status: 'error', message: 'Bounce tables missing' }
        end
      rescue StandardError => e
        { status: 'error', message: e.message }
      end
    end
  end
end
