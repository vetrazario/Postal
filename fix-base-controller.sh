#!/bin/bash
# Скрипт для исправления BaseController на сервере

cat > /tmp/base_controller_fix.rb << 'EOF'
# frozen_string_literal: true

module Dashboard
  class BaseController < ActionController::Base
    # Skip CSRF for now (dashboard is internal)
    skip_before_action :verify_authenticity_token
    
    # Use modern dashboard layout with full navigation
    layout 'dashboard'
    
    before_action :authenticate_dashboard_user!

    private

    def authenticate_dashboard_user!
      authenticate_or_request_with_http_basic('Dashboard') do |username, password|
        expected_username = ENV.fetch('DASHBOARD_USERNAME', 'admin')
        expected_password = ENV.fetch('DASHBOARD_PASSWORD', '')

        ActiveSupport::SecurityUtils.secure_compare(username, expected_username) &&
          ActiveSupport::SecurityUtils.secure_compare(password, expected_password)
      end
    end
  end
end
EOF

echo "📝 Применение исправления BaseController..."
docker compose cp /tmp/base_controller_fix.rb api:/app/app/controllers/dashboard/base_controller.rb
docker compose exec api chown root:root /app/app/controllers/dashboard/base_controller.rb

echo "🔄 Перезапуск контейнера API..."
docker compose restart api

echo "✅ Готово! Проверьте дашборд через несколько секунд."

