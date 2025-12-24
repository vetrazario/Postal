module Api
  module V1
    class HealthController < ActionController::API
      def show
        checks = { database: check_database, redis: check_redis }
        healthy = checks.values.all? { |c| c[:status] == 'ok' }

        render json: {
          status: healthy ? 'healthy' : 'degraded',
          timestamp: Time.current.iso8601,
          checks: checks
        }, status: healthy ? :ok : :service_unavailable
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
    end
  end
end
