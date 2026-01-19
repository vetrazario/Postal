require 'sidekiq/web'
require_relative '../lib/sidekiq_web_auth'

# Sidekiq Web UI authentication
# Uses SidekiqWebAuth to check credentials from SystemConfig (database) or ENV
Sidekiq::Web.use(Rack::Auth::Basic, 'Sidekiq') do |username, password|
  SidekiqWebAuth.authenticate(username, password)
end

Rails.application.routes.draw do
  # Tracking endpoints (public, no auth)
  get '/go/:slug', to: 'tracking#click', as: 'track_click_readable'
  get '/t/c/:token', to: 'tracking#click', as: 'track_click'
  get '/t/o/:token', to: 'tracking#open', as: 'track_open'
  get '/unsubscribe', to: 'unsubscribes#show', as: 'unsubscribe_page'
  post '/unsubscribe', to: 'unsubscribes#create', as: 'unsubscribe_submit'

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

      # Internal endpoints (for service communication)
      namespace :internal do
        get 'smtp_relay_config', to: 'config#smtp_relay'
        post 'smtp_auth', to: 'config#smtp_auth'
        post 'tracking_event', to: 'tracking#event'
      end
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
        post :regenerate_password
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

    # Analytics
    resource :analytics, only: [:show] do
      get :hourly
      get :daily
      get :campaigns
    end

    # AI Analytics
    resource :ai_analytics, only: [:show] do
      post :analyze_bounces
      post :optimize_timing
      post :compare_campaigns
      get :history
    end

    # Settings
    resource :settings, only: [:show, :update] do
      patch :update_system_config, on: :collection
      post :test_ams_connection, on: :collection
      post :test_postal_connection, on: :collection
      post :test_smtp_relay_connection, on: :collection
      post :generate_smtp_credentials, on: :collection
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

    # Tracking Settings
    resource :tracking_settings, only: [:show, :update] do
      post :enable_warmup, on: :collection
      post :disable_warmup, on: :collection
      get :check_reputation, on: :collection
    end
  end

  # Sidekiq Web UI
  # Authentication is handled by SidekiqWebAuth middleware (reads from SystemConfig or ENV)
  mount Sidekiq::Web => '/sidekiq' if defined?(Sidekiq::Web)
end

