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
        connection = ActiveRecord::Base.connection
        
        bounced_exists = false
        unsubscribes_exists = false
        
        begin
          # Используем table_exists? с логированием для диагностики
          bounced_exists = connection.table_exists?('bounced_emails')
          Rails.logger.debug "bounced_emails table_exists?: #{bounced_exists.inspect}"
          
          unsubscribes_exists = connection.table_exists?('unsubscribes')
          Rails.logger.debug "unsubscribes table_exists?: #{unsubscribes_exists.inspect}"
          
          # Если table_exists? не работает, пробуем через SQL
          unless bounced_exists
            result = connection.execute("SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'bounced_emails')")
            bounced_exists = result.first.values.first == true || result.first.values.first == 't'
            Rails.logger.debug "bounced_emails SQL check: #{bounced_exists.inspect}"
          end
          
          unless unsubscribes_exists
            result = connection.execute("SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'unsubscribes')")
            unsubscribes_exists = result.first.values.first == true || result.first.values.first == 't'
            Rails.logger.debug "unsubscribes SQL check: #{unsubscribes_exists.inspect}"
          end
        rescue StandardError => e
          Rails.logger.error "check_bounce_tables error: #{e.message}\n#{e.backtrace.join("\n")}"
        end
        
        if bounced_exists && unsubscribes_exists
          { status: 'ok' }
        else
          { status: 'error', message: "Bounce tables missing (bounced: #{bounced_exists}, unsub: #{unsubscribes_exists})" }
        end
      end
    end
  end
end
