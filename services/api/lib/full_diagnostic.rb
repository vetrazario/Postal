# frozen_string_literal: true

# Full System Diagnostic Script
# Run: docker compose exec api rails runner lib/full_diagnostic.rb

class FullDiagnostic
  SMTP_USER = 'smtp_1759d730301c8640'
  SMTP_PASS = 'HavkfC025ydZYDJDdAcqv7u7'

  attr_reader :errors, :warnings, :passed

  def initialize
    @errors = []
    @warnings = []
    @passed = []
  end

  def run_all
    puts "\n" + "=" * 60
    puts "FULL SYSTEM DIAGNOSTIC"
    puts "=" * 60 + "\n"

    # 1. Database
    test_database_connection
    test_database_migrations
    test_all_models

    # 2. Redis
    test_redis_connection

    # 3. Sidekiq
    test_sidekiq

    # 4. SMTP Auth
    test_smtp_credentials
    test_smtp_connection

    # 5. Models - create test records
    test_create_email_log
    test_create_delivery_error
    test_create_email_click
    test_create_email_open
    test_create_tracking_event
    test_create_unsubscribe

    # 6. Services
    test_link_tracker
    test_error_classifier
    test_postal_client_config

    # 7. Routes
    test_routes_exist

    # 8. Environment
    test_environment_variables

    # 9. Config files
    test_config_files

    # Print summary
    print_summary
  end

  private

  def test(name)
    print "Testing: #{name}... "
    begin
      result = yield
      if result == true || result.nil?
        puts "\e[32mPASS\e[0m"
        @passed << name
      else
        puts "\e[33mWARN: #{result}\e[0m"
        @warnings << "#{name}: #{result}"
      end
    rescue => e
      puts "\e[31mFAIL: #{e.message}\e[0m"
      @errors << "#{name}: #{e.class} - #{e.message}"
    end
  end

  # ============ DATABASE ============

  def test_database_connection
    test("Database connection") do
      ActiveRecord::Base.connection.active?
    end
  end

  def test_database_migrations
    test("Database migrations up-to-date") do
      pending = ActiveRecord::Migration.check_all_pending!
      true
    rescue ActiveRecord::PendingMigrationError => e
      "Pending migrations: #{e.message}"
    end
  end

  def test_all_models
    models = [
      EmailLog, EmailClick, EmailOpen, DeliveryError,
      TrackingEvent, Unsubscribe, BouncedEmail, CampaignStats,
      SmtpCredential, SystemConfig, WebhookEndpoint
    ]

    models.each do |model|
      test("Model #{model.name} loadable") do
        model.table_exists? ? true : "Table does not exist"
      end
    end

    # Check columns exist
    test("DeliveryError has occurred_at column") do
      DeliveryError.column_names.include?('occurred_at') ? true : "Missing occurred_at column"
    end

    test("DeliveryError has category column") do
      DeliveryError.column_names.include?('category') ? true : "Missing category column"
    end

    test("DeliveryError has smtp_message column") do
      DeliveryError.column_names.include?('smtp_message') ? true : "Missing smtp_message column"
    end

    test("EmailClick has campaign_id column") do
      EmailClick.column_names.include?('campaign_id') ? true : "Missing campaign_id column"
    end

    test("EmailOpen has campaign_id column") do
      EmailOpen.column_names.include?('campaign_id') ? true : "Missing campaign_id column"
    end

    # Check nullable constraints
    test("DeliveryError.email_log_id is nullable") do
      col = DeliveryError.columns_hash['email_log_id']
      col.null ? true : "email_log_id is NOT NULL - needs migration"
    end

    test("EmailClick.email_log_id is nullable") do
      col = EmailClick.columns_hash['email_log_id']
      col.null ? true : "email_log_id is NOT NULL - needs migration"
    end

    test("EmailOpen.email_log_id is nullable") do
      col = EmailOpen.columns_hash['email_log_id']
      col.null ? true : "email_log_id is NOT NULL - needs migration"
    end
  end

  # ============ REDIS ============

  def test_redis_connection
    test("Redis connection") do
      redis_url = ENV['REDIS_URL'] || 'redis://localhost:6379'
      redis = Redis.new(url: redis_url)
      result = redis.ping
      result == 'PONG' ? true : "Unexpected response: #{result}"
    end
  end

  # ============ SIDEKIQ ============

  def test_sidekiq
    test("Sidekiq processes running") do
      processes = Sidekiq::ProcessSet.new.size
      processes > 0 ? true : "No Sidekiq processes found"
    end

    test("Sidekiq retry queue") do
      retries = Sidekiq::RetrySet.new.size
      if retries > 0
        "#{retries} jobs in retry queue - consider clearing"
      else
        true
      end
    end

    test("Sidekiq dead queue") do
      dead = Sidekiq::DeadSet.new.size
      if dead > 0
        "#{dead} jobs in dead queue - consider clearing"
      else
        true
      end
    end
  end

  # ============ SMTP ============

  def test_smtp_credentials
    test("SMTP credentials in database") do
      cred = SmtpCredential.find_by(username: SMTP_USER)
      if cred.nil?
        "Credential not found for #{SMTP_USER}"
      elsif !cred.active?
        "Credential exists but is not active"
      else
        true
      end
    end

    test("SMTP credential authentication") do
      cred = SmtpCredential.find_by(username: SMTP_USER)
      if cred.nil?
        "Credential not found"
      elsif cred.authenticate(SMTP_PASS)
        true
      else
        "Password does not match"
      end
    end
  end

  def test_smtp_connection
    test("SMTP relay port reachable (2525)") do
      require 'socket'
      begin
        socket = TCPSocket.new('127.0.0.1', 2525)
        socket.close
        true
      rescue Errno::ECONNREFUSED
        "Port 2525 not listening - Haraka not running?"
      rescue => e
        e.message
      end
    end

    test("SMTP AUTH via Haraka") do
      require 'net/smtp'
      begin
        smtp = Net::SMTP.new('127.0.0.1', 2525)
        smtp.open_timeout = 5
        smtp.read_timeout = 5
        smtp.start('localhost', SMTP_USER, SMTP_PASS, :plain) do |s|
          # Connected successfully
        end
        true
      rescue Net::SMTPAuthenticationError => e
        "Auth failed: #{e.message}"
      rescue Net::OpenTimeout
        "Connection timeout - Haraka not responding"
      rescue Errno::ECONNREFUSED
        "Connection refused - Haraka not running"
      rescue => e
        "#{e.class}: #{e.message}"
      end
    end
  end

  # ============ MODEL CREATION TESTS ============

  def test_create_email_log
    test("Create EmailLog") do
      log = EmailLog.create!(
        message_id: "test-#{SecureRandom.hex(8)}@diagnostic.test",
        recipient: "test@example.com",
        sender: "sender@example.com",
        subject: "Diagnostic Test",
        status: "queued",
        campaign_id: "diag-test"
      )
      log.destroy
      true
    end
  end

  def test_create_delivery_error
    test("Create DeliveryError (without email_log)") do
      err = DeliveryError.create!(
        campaign_id: "diag-test",
        category: "unknown",
        smtp_message: "Test error",
        occurred_at: Time.current
      )
      err.destroy
      true
    end
  end

  def test_create_email_click
    test("Create EmailClick (without email_log)") do
      click = EmailClick.create!(
        token: SecureRandom.urlsafe_base64(32),
        url: "https://example.com/test",
        campaign_id: "diag-test"
      )
      click.destroy
      true
    end
  end

  def test_create_email_open
    test("Create EmailOpen (without email_log)") do
      open_record = EmailOpen.create!(
        token: SecureRandom.urlsafe_base64(32),
        campaign_id: "diag-test"
      )
      open_record.destroy
      true
    end
  end

  def test_create_tracking_event
    test("Create TrackingEvent (without email_log)") do
      event = TrackingEvent.create!(
        event_type: "sent"
      )
      event.destroy
      true
    end
  end

  def test_create_unsubscribe
    test("Create Unsubscribe") do
      unsub = Unsubscribe.create!(
        email: "unsub-test-#{SecureRandom.hex(4)}@example.com"
      )
      unsub.destroy
      true
    end
  end

  # ============ SERVICES ============

  def test_link_tracker
    test("LinkTracker service") do
      # Create temp email log for tracker
      log = EmailLog.create!(
        message_id: "tracker-test-#{SecureRandom.hex(8)}@diagnostic.test",
        recipient: "test@example.com",
        sender: "sender@example.com",
        subject: "Tracker Test",
        status: "queued",
        campaign_id: "diag-test"
      )

      tracker = LinkTracker.new(email_log: log, track_clicks: false, track_opens: false, add_footer: false)
      html = "<html><body><a href='https://google.com'>Link</a></body></html>"
      result = tracker.track_links(html)

      log.destroy
      result.include?('href') ? true : "Tracking failed"
    end
  end

  def test_error_classifier
    test("ErrorClassifier service") do
      result = ErrorClassifier.classify({ output: "550 User not found" })
      result[:category].present? ? true : "Classification failed"
    end
  end

  def test_postal_client_config
    test("PostalClient configuration") do
      api_url = ENV['POSTAL_API_URL']
      api_key = ENV['POSTAL_API_KEY']

      if api_url.blank?
        "POSTAL_API_URL not set"
      elsif api_key.blank?
        "POSTAL_API_KEY not set"
      else
        true
      end
    end
  end

  # ============ ROUTES ============

  def test_routes_exist
    routes = Rails.application.routes.routes

    required_routes = [
      { path: '/t/c/:token', name: 'track_click' },
      { path: '/t/o/:token', name: 'track_open' },
      { path: '/go/:slug', name: 'track_click_readable' },
      { path: '/unsubscribe', name: 'unsubscribe_page' },
      { path: '/api/v1/smtp/receive', name: 'smtp_receive' },
      { path: '/api/v1/health', name: 'health' },
      { path: '/dashboard', name: 'dashboard_root' },
    ]

    required_routes.each do |req|
      test("Route exists: #{req[:path]}") do
        found = routes.any? do |r|
          r.path.spec.to_s.include?(req[:path].gsub(':token', '').gsub(':slug', ''))
        end
        found ? true : "Route not found"
      end
    end

    test("Root route defined") do
      begin
        Rails.application.routes.url_helpers.root_path
        true
      rescue NoMethodError
        "root_path not defined"
      end
    end
  end

  # ============ ENVIRONMENT ============

  def test_environment_variables
    required_vars = %w[
      RAILS_ENV
      REDIS_URL
      DATABASE_URL
      POSTAL_API_KEY
      POSTAL_API_URL
      SECRET_KEY_BASE
    ]

    optional_vars = %w[
      DOMAIN
      TRACKING_DOMAIN
      SMTP_RELAY_HOST
      SMTP_RELAY_PORT
    ]

    required_vars.each do |var|
      test("ENV[#{var}] set") do
        ENV[var].present? ? true : "Not set"
      end
    end

    optional_vars.each do |var|
      test("ENV[#{var}] (optional)") do
        ENV[var].present? ? true : "Not set (optional)"
      end
    end
  end

  # ============ CONFIG FILES ============

  def test_config_files
    files = [
      'config/bounce_patterns.yml',
      'config/database.yml',
      'config/routes.rb',
      'app/views/layouts/application.html.erb',
      'app/views/layouts/unsubscribes.html.erb',
    ]

    files.each do |file|
      test("Config file exists: #{file}") do
        path = Rails.root.join(file)
        File.exist?(path) ? true : "File not found"
      end
    end
  end

  # ============ SUMMARY ============

  def print_summary
    puts "\n" + "=" * 60
    puts "DIAGNOSTIC SUMMARY"
    puts "=" * 60

    puts "\n\e[32mPASSED: #{@passed.count}\e[0m"

    if @warnings.any?
      puts "\n\e[33mWARNINGS: #{@warnings.count}\e[0m"
      @warnings.each { |w| puts "  - #{w}" }
    end

    if @errors.any?
      puts "\n\e[31mERRORS: #{@errors.count}\e[0m"
      @errors.each { |e| puts "  - #{e}" }
    end

    puts "\n" + "=" * 60

    if @errors.empty?
      puts "\e[32mAll critical tests passed!\e[0m"
    else
      puts "\e[31mFix #{@errors.count} error(s) before proceeding!\e[0m"
    end

    puts "=" * 60 + "\n"
  end
end

# Run diagnostic
FullDiagnostic.new.run_all
