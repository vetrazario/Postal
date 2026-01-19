class ApplicationController < ActionController::API
  include ActionController::HttpAuthentication::Token::ControllerMethods

  before_action :authenticate_api_key
  before_action :set_request_id

  rescue_from StandardError, with: :handle_error
  rescue_from ActiveRecord::RecordNotFound, with: :handle_not_found
  rescue_from ActiveRecord::RecordInvalid, with: :handle_validation_error
  rescue_from ActionController::ParameterMissing, with: :handle_parameter_missing

  private

  def authenticate_api_key
    authenticated = authenticate_or_request_with_http_token do |token, _options|
      @api_key = ApiKeyAuthenticator.call(token)
      @api_key.present?
    end
    
    # Если аутентификация не удалась, устанавливаем флаг для Rack::Attack
    # (хотя Rack::Attack уже отработал, это может быть полезно для логирования)
    if !authenticated && request.env['HTTP_AUTHORIZATION'].present?
      request.env['rack.attack.failed_auth'] = true
    end
    
    authenticated
  end

  def current_api_key
    @api_key
  end

  def set_request_id
    @request_id = SecureRandom.hex(12)
  end

  def handle_error(exception)
    Rails.logger.error "#{exception.class}: #{exception.message}\n#{exception.backtrace.join("\n")}"
    
    render json: {
      error: {
        code: "internal_error",
        message: "An internal error occurred"
      },
      request_id: @request_id
    }, status: :internal_server_error
  end

  def handle_not_found(exception)
    render json: {
      error: {
        code: "not_found",
        message: "Resource not found"
      },
      request_id: @request_id
    }, status: :not_found
  end

  def handle_validation_error(exception)
    render json: {
      error: {
        code: "validation_error",
        message: "Validation failed",
        details: exception.record.errors.full_messages.map { |msg| { message: msg } }
      },
      request_id: @request_id
    }, status: :unprocessable_entity
  end

  def handle_parameter_missing(exception)
    render json: {
      error: {
        code: "parameter_missing",
        message: "Missing required parameter",
        details: exception.param
      },
      request_id: @request_id
    }, status: :bad_request
  end
end





