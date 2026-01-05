# frozen_string_literal: true

module Dashboard
  class BaseController < ActionController::Base
    # Skip CSRF verification for API endpoints but keep for HTML forms
    protect_from_forgery with: :exception, unless: -> { request.format.json? }

    before_action :authenticate_dashboard_user!

    # Add helper for layouts
    layout 'dashboard'

    # Include view helpers
    helper :all

    private

    def authenticate_dashboard_user!
      expected_password = ENV['DASHBOARD_PASSWORD']

      # Require password to be explicitly set - empty password is a security risk
      if expected_password.blank?
        Rails.logger.error "DASHBOARD_PASSWORD environment variable is not set!"
        render plain: "Dashboard access disabled. Set DASHBOARD_PASSWORD environment variable.", status: :service_unavailable
        return
      end

      authenticate_or_request_with_http_basic('Dashboard') do |username, password|
        expected_username = ENV.fetch('DASHBOARD_USERNAME', 'admin')

        ActiveSupport::SecurityUtils.secure_compare(username, expected_username) &&
          ActiveSupport::SecurityUtils.secure_compare(password, expected_password)
      end
    end
  end
end
