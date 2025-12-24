require 'sidekiq/web'

# Sidekiq Web UI authentication
# Монтируем только если заданы учетные данные
if ENV['SIDEKIQ_WEB_USERNAME'].present? && ENV['SIDEKIQ_WEB_PASSWORD'].present?
  Sidekiq::Web.use(Rack::Auth::Basic) do |username, password|
    expected_username = ENV.fetch('SIDEKIQ_WEB_USERNAME')
    expected_password = ENV.fetch('SIDEKIQ_WEB_PASSWORD')
    
    ActiveSupport::SecurityUtils.secure_compare(
      ::Digest::SHA256.hexdigest(username.to_s),
      ::Digest::SHA256.hexdigest(expected_username)
    ) & ActiveSupport::SecurityUtils.secure_compare(
      ::Digest::SHA256.hexdigest(password.to_s),
      ::Digest::SHA256.hexdigest(expected_password)
    )
  end
end

Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      # Health check (no auth)
      get 'health', to: 'health#show'
      
      # Email sending
      post 'send', to: 'emails#send_email'
      post 'batch', to: 'batches#create'
      
      # Status
      get 'status/:message_id', to: 'status#show', as: 'status'
      
      # Statistics
      get 'stats', to: 'stats#index'
      
      # Templates
      post 'templates', to: 'templates#create'
      
      # Webhooks (from Postal)
      post 'webhook', to: 'webhooks#postal'
    end
  end
  
  # Dashboard (web interface)
  get 'dashboard', to: 'dashboard#index', as: 'dashboard_index'
  get 'dashboard/logs', to: 'dashboard#logs', as: 'dashboard_logs'
  
  # Sidekiq Web UI (монтируем только если заданы учетные данные)
  if defined?(Sidekiq::Web) && ENV['SIDEKIQ_WEB_USERNAME'].present? && ENV['SIDEKIQ_WEB_PASSWORD'].present?
    mount Sidekiq::Web => '/sidekiq'
  end
end

