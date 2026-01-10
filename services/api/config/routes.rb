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

      # SMTP Relay endpoint (from Haraka)
      post 'smtp/receive', to: 'smtp#receive'

      # Status
      get 'status/:message_id', to: 'status#show', as: 'status'

      # Statistics
      get 'stats', to: 'stats#index'

      # Templates
      post 'templates', to: 'templates#create'

      # Webhooks (from Postal)
      post 'webhook', to: 'webhooks#postal'

      # Bounce status check
      get 'bounce_status/check', to: 'bounce_status#check'
    end
  end

  # Dashboard (web interface)
  namespace :dashboard do
    root to: 'dashboard#index'

    # API Keys
    resources :api_keys, except: [:show] do
      member do
        patch :toggle_active
      end
    end

    # SMTP Credentials
    resources :smtp_credentials, except: [:show] do
      member do
        patch :toggle_active
        post :test_connection
      end
    end

    # Webhooks
    resources :webhooks do
      member do
        post :test
        post :retry_failed
      end
      collection do
        get :logs
      end
    end

    # Templates
    resources :templates

    # Logs
    resources :logs, only: [:index, :show] do
      collection do
        get :export
        get :export_unsubscribes
        get :export_bounces
      end
    end

    # Analytics (unified with AI Analytics)
    resource :analytics, only: [:show] do
      get :hourly, on: :member
      get :daily, on: :member
      get :campaigns, on: :member
      post :analyze_campaign, on: :member
      post :analyze_bounces, on: :member
      post :optimize_timing, on: :member
      post :compare_campaigns, on: :member
      get :history, on: :member
      get :export_opens, on: :member
      get :export_clicks, on: :member
      get :export_unsubscribes, on: :member
      get :export_bounces, on: :member
    end

    # Settings
    resource :settings, only: [:show, :update] do
      patch :update_system_config, on: :collection
      post :test_ams_connection, on: :collection
      post :test_postal_connection, on: :collection
      post :apply_changes, on: :collection
    end

    # Mailing Rules
    resource :mailing_rules, only: [:show, :update] do
      post :test_ams_connection
    end

    # Error Monitor
    resources :error_monitor, only: [:index] do
      collection do
        get :stats
      end
    end
  end

  # Sidekiq Web UI (монтируем только если заданы учетные данные)
  if defined?(Sidekiq::Web) && ENV['SIDEKIQ_WEB_USERNAME'].present? && ENV['SIDEKIQ_WEB_PASSWORD'].present?
    mount Sidekiq::Web => '/sidekiq'
  end
end

