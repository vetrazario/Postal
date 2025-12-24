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

  # GET /health
  get '/health' do
    content_type :json
    { status: 'healthy', timestamp: Time.now.iso8601 }.to_json
  end
end




