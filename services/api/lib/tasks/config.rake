# frozen_string_literal: true

namespace :config do
  desc 'Generate postal.yml from template using environment variables'
  task generate_postal_config: :environment do
    template_path = Rails.root.join('..', '..', 'config', 'postal.yml.template')
    output_path = Rails.root.join('..', '..', 'config', 'postal.yml')

    unless File.exist?(template_path)
      puts "❌ Error: Template file not found at #{template_path}"
      exit 1
    end

    template = File.read(template_path)

    # Replace ${VAR} with actual environment variable values
    output = template.gsub(/\$\{(\w+)\}/) do |match|
      var_name = $1
      value = ENV[var_name]

      if value.nil? || value.empty?
        puts "⚠️  Warning: Environment variable #{var_name} is not set"
        match # Keep placeholder if variable not set
      else
        value
      end
    end

    File.write(output_path, output)
    puts "✅ Generated #{output_path} from template"
    puts "   Template: #{template_path}"
  end

  desc 'Sync SystemConfig to .env file'
  task sync_to_env: :environment do
    config = SystemConfig.instance
    env_path = Rails.root.join('..', '..', '.env')

    if config.sync_to_env_file(env_path)
      puts "✅ Successfully synced SystemConfig to #{env_path}"
    else
      puts "❌ Failed to sync SystemConfig to .env file"
      exit 1
    end
  end

  desc 'Load SystemConfig from .env file (or current ENV)'
  task load_from_env: :environment do
    config = SystemConfig.instance

    # Load .env file if it exists
    env_path = Rails.root.join('..', '..', '.env')
    if File.exist?(env_path)
      puts "📂 Loading environment variables from #{env_path}..."
      File.readlines(env_path).each do |line|
        line = line.strip
        next if line.empty? || line.start_with?('#')

        key, value = line.split('=', 2)
        ENV[key] = value if key && value
      end
    end

    # Update SystemConfig from ENV
    updates = {}

    # Server
    updates[:domain] = ENV['DOMAIN'] if ENV['DOMAIN'].present?
    updates[:allowed_sender_domains] = ENV['ALLOWED_SENDER_DOMAINS'] if ENV['ALLOWED_SENDER_DOMAINS'].present?
    updates[:cors_origins] = ENV['CORS_ORIGINS'] if ENV['CORS_ORIGINS'].present?

    # AMS
    updates[:ams_callback_url] = ENV['AMS_CALLBACK_URL'] if ENV['AMS_CALLBACK_URL'].present?
    updates[:ams_api_key] = ENV['AMS_API_KEY'] if ENV['AMS_API_KEY'].present?
    updates[:ams_api_url] = ENV['AMS_API_URL'] if ENV['AMS_API_URL'].present?

    # Postal
    updates[:postal_api_url] = ENV['POSTAL_API_URL'] if ENV['POSTAL_API_URL'].present?
    updates[:postal_api_key] = ENV['POSTAL_API_KEY'] if ENV['POSTAL_API_KEY'].present?
    updates[:postal_signing_key] = ENV['POSTAL_SIGNING_KEY'] if ENV['POSTAL_SIGNING_KEY'].present?

    # Limits
    updates[:daily_limit] = ENV['DAILY_LIMIT'].to_i if ENV['DAILY_LIMIT'].present?
    updates[:sidekiq_concurrency] = ENV['SIDEKIQ_CONCURRENCY'].to_i if ENV['SIDEKIQ_CONCURRENCY'].present?
    updates[:webhook_secret] = ENV['WEBHOOK_SECRET'] if ENV['WEBHOOK_SECRET'].present?

    if updates.any?
      if config.update(updates)
        puts "✅ Successfully loaded #{updates.keys.size} configuration values into SystemConfig"
        puts "   Updated fields: #{updates.keys.join(', ')}"
      else
        puts "❌ Failed to update SystemConfig:"
        config.errors.full_messages.each do |error|
          puts "   - #{error}"
        end
        exit 1
      end
    else
      puts "ℹ️  No configuration values found in environment to load"
    end
  end

  desc 'Show current SystemConfig values'
  task show: :environment do
    config = SystemConfig.instance

    puts "\n📋 Current System Configuration:\n\n"

    puts "🖥️  Server:"
    puts "   Domain: #{config.domain}"
    puts "   Allowed Sender Domains: #{config.allowed_sender_domains || '(not set)'}"
    puts "   CORS Origins: #{config.cors_origins || '(not set)'}"
    puts ""

    puts "🔗 AMS Integration:"
    puts "   Callback URL: #{config.ams_callback_url || '(not set)'}"
    puts "   API URL: #{config.ams_api_url || '(not set)'}"
    puts "   API Key: #{config.ams_api_key.present? ? '***' + config.ams_api_key[-4..-1] : '(not set)'}"
    puts ""

    puts "📧 Postal:"
    puts "   API URL: #{config.postal_api_url}"
    puts "   API Key: #{config.postal_api_key.present? ? '***' + config.postal_api_key[-4..-1] : '(not set)'}"
    puts "   Signing Key: #{config.postal_signing_key.present? ? '***' + config.postal_signing_key[-4..-1] : '(not set)'}"
    puts ""

    puts "🔒 Limits & Security:"
    puts "   Daily Limit: #{config.daily_limit} emails/day"
    puts "   Sidekiq Concurrency: #{config.sidekiq_concurrency} threads"
    puts "   Webhook Secret: #{config.webhook_secret.present? ? '***' + config.webhook_secret[-4..-1] : '(not set)'}"
    puts ""

    if config.restart_required?
      puts "⚠️  Services requiring restart: #{config.restart_services.join(', ')}"
      puts ""
    end
  end

  desc 'Test AMS connection'
  task test_ams: :environment do
    config = SystemConfig.instance
    puts "🔍 Testing AMS connection..."
    puts "   URL: #{config.ams_callback_url}"

    result = config.test_ams_connection

    if result[:success]
      puts "✅ AMS connection successful: #{result[:message]}"
    else
      puts "❌ AMS connection failed: #{result[:error]}"
      exit 1
    end
  end

  desc 'Test Postal connection'
  task test_postal: :environment do
    config = SystemConfig.instance
    puts "🔍 Testing Postal connection..."
    puts "   URL: #{config.postal_api_url}"

    result = config.test_postal_connection

    if result[:success]
      puts "✅ Postal connection successful: #{result[:message]}"
    else
      puts "❌ Postal connection failed: #{result[:error]}"
      exit 1
    end
  end
end
