require 'sinatra/base'
require 'pg'
require 'redis'
require 'base64'
require 'json'
require 'sidekiq'
require_relative 'lib/tracking_handler'
require_relative 'lib/event_logger'
require_relative 'lib/webhook_sender'

class TrackingApp < Sinatra::Base
  configure do
    set :database_url, ENV.fetch("DATABASE_URL", "postgres://email_sender:password@localhost:5432/email_sender")
    set :redis_url, ENV.fetch("REDIS_URL", "redis://localhost:6379/0")
  end

  # GET /track/o - Open tracking (pixel)
  get '/track/o' do
    handler = TrackingHandler.new(
      database_url: settings.database_url,
      redis_url: settings.redis_url
    )
    
    result = handler.handle_open(
      eid: params[:eid],
      cid: params[:cid],
      mid: params[:mid],
      ip: request.ip,
      user_agent: request.user_agent
    )
    
    if result[:success]
      # Return 1x1 transparent PNG
      content_type 'image/png'
      send_file File.join(settings.public_folder, 'pixel.png'), type: 'image/png', disposition: 'inline'
    else
      status 404
      "Not found"
    end
  end

  # GET /track/c - Click tracking (redirect)
  get '/track/c' do
    handler = TrackingHandler.new(
      database_url: settings.database_url,
      redis_url: settings.redis_url
    )
    
    result = handler.handle_click(
      url: params[:url],
      eid: params[:eid],
      cid: params[:cid],
      mid: params[:mid],
      ip: request.ip,
      user_agent: request.user_agent
    )
    
    if result[:success]
      redirect result[:url], 302
    else
      status 404
      "Not found"
    end
  end

  # GET /unsubscribe - Unsubscribe page
  get '/unsubscribe' do
    handler = TrackingHandler.new(
      database_url: settings.database_url,
      redis_url: settings.redis_url
    )

    result = handler.handle_unsubscribe(
      eid: params[:eid],
      cid: params[:cid],
      ip: request.ip,
      user_agent: request.user_agent
    )

    if result[:success]
      content_type 'text/html'
      <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Unsubscribe</title>
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                   display: flex; justify-content: center; align-items: center; min-height: 100vh;
                   margin: 0; background: #f5f5f5; }
            .card { background: white; padding: 40px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1);
                    text-align: center; max-width: 400px; }
            h1 { color: #333; margin-bottom: 16px; }
            p { color: #666; margin-bottom: 24px; }
            .email { font-weight: bold; color: #333; }
            .success { color: #28a745; }
          </style>
        </head>
        <body>
          <div class="card">
            <h1 class="success">✓ Unsubscribed</h1>
            <p>Email <span class="email">#{result[:email_masked]}</span> has been unsubscribed.</p>
            <p>You will no longer receive emails from this campaign.</p>
          </div>
        </body>
        </html>
      HTML
    else
      status 400
      content_type 'text/html'
      <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <title>Unsubscribe Error</title>
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                   display: flex; justify-content: center; align-items: center; min-height: 100vh;
                   margin: 0; background: #f5f5f5; }
            .card { background: white; padding: 40px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1);
                    text-align: center; max-width: 400px; }
            h1 { color: #dc3545; }
          </style>
        </head>
        <body>
          <div class="card">
            <h1>Error</h1>
            <p>Invalid or expired unsubscribe link.</p>
          </div>
        </body>
        </html>
      HTML
    end
  end

  # POST /unsubscribe - One-Click Unsubscribe (RFC 8058)
  post '/unsubscribe' do
    handler = TrackingHandler.new(
      database_url: settings.database_url,
      redis_url: settings.redis_url
    )

    result = handler.handle_unsubscribe(
      eid: params[:eid],
      cid: params[:cid],
      ip: request.ip,
      user_agent: request.user_agent
    )

    if result[:success]
      status 200
      content_type :json
      { success: true, message: 'Unsubscribed successfully' }.to_json
    else
      status 400
      content_type :json
      { success: false, error: 'Invalid request' }.to_json
    end
  end

  # GET /health
  get '/health' do
    content_type :json
    { status: 'healthy', timestamp: Time.now.iso8601 }.to_json
  end
end




