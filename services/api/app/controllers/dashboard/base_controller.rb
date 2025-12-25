# frozen_string_literal: true

module Dashboard
  class BaseController < ApplicationController
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
