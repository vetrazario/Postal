# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your database
# schema. If you need to create the application database on another system, you should be using
# db/schema.rb instead so that the schema's last checked-in version is the state that the
# application's structure requires for proper migrations.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_01_18_16_39_457323) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "uuid-ossp"
  enable_extension "pg_stat_statements"

  create_table "api_keys", force: :cascade do |t|
    t.string :key_hash, null: false
    t.string :name, null: false
    t.boolean :active, null: false, default: true
    t.string :description, null: true
    t.datetime :last_used_at, null: true
    t.timestamps null: false
  end

  create_table "email_templates", force: :cascade do |t|
    t.string :name, null: false
    t.text :subject, null: false
    t.text :html_body, null: false
    t.text :text_body, null: true
    t.timestamps null: false
  end

  create_table "email_logs", force: :cascade do |t|
    t.string :message_id, null: false
    t.string :recipient, null: false
    t.string :recipient_masked, null: true
    t.string :sender, null: true
    t.string :subject, null: true
    t.text :html_body, null: true
    t.string :status, null: false
    t.string :campaign_id, null: true
    t.string :campaign_name, null: true
    t.string :template_id, null: true
    t.json :metadata, null: true
    t.string :smtp_message, null: true
    t.string :postal_message_id, null: true
    t.string :bounce_type, null: true
    t.string :bounce_category, null: true
    t.string :bounce_reason, null: true
    t.integer :click_count, null: false, default: 0
    t.integer :open_count, null: false, default: 0
    t.string :ip_address, null: true
    t.string :user_agent, null: true
    t.string :list_unsubscribe_url, null: true
    t.json :tracking_data, null: true
    t.timestamps null: false

    t.index ["status"]
    t.index ["campaign_id"]
    t.index ["created_at"]
    t.index ["ip_address"]
    t.index ["campaign_id", "status"]
  end

  create_table "tracking_events", force: :cascade do |t|
    t.string :event_type, null: false
    t.integer :email_log_id, null: false
    t.string :data, null: true
    t.timestamp :timestamp, null: false
    t.timestamps null: false

    t.index ["event_type"]
    t.index ["email_log_id"]
  end

  create_table "campaign_stats", force: :cascade do |t|
    t.string :campaign_id, null: false
    t.string :campaign_name, null: true
    t.integer :sent, null: false, default: 0
    t.integer :delivered, null: false, default: 0
    t.integer :bounced, null: false, default: 0
    t.integer :failed, null: false, default: 0
    t.integer :queued, null: false, default: 0
    t.integer :complained, null: false, default: 0
    t.timestamps null: false

    t.index ["campaign_id"]
    t.index ["created_at"]
  end

  create_table "smtp_credentials", force: :cascade do |t|
    t.string :username, null: false
    t.string :password_encrypted, null: false
    t.boolean :active, null: false, default: true
    t.string :description, null: true
    t.timestamps null: false
  end

  create_table "webhook_endpoints", force: :cascade do |t|
    t.string :url, null: false
    t.string :secret, null: false
    t.boolean :active, null: false, default: true
    t.string :description, null: true
    t.json :headers, null: true
    t.timestamps null: false
  end

  create_table "webhook_logs", force: :cascade do |t|
    t.bigint :webhook_endpoint_id, null: false
    t.string :event_type, null: false
    t.json :payload, null: true
    t.integer :status_code, null: false
    t.string :error_message, null: true
    t.timestamp :request_sent_at, null: false
    t.timestamp :response_received_at, null: true
    t.string :trace, null: true
    t.timestamps null: false

    t.index ["webhook_endpoint_id"]
    t.index ["event_type"]
    t.index ["request_sent_at"]
  end

  create_table "ai_settings", force: :cascade do |t|
    t.string :provider, null: false
    t.string :model, null: false
    t.string :api_key, null: false
    t.boolean :enabled, null: false, default: false
    t.json :settings, null: true
    t.timestamps null: false
  end

  create_table "ai_analyses", force: :cascade do |t|
    t.bigint :email_log_id, null: false
    t.string :provider, null: false
    t.string :model, null: false
    t.string :analysis_type, null: false
    t.text :result, null: true
    t.json :metadata, null: true
    t.string :status, null: false
    t.datetime :analyzed_at, null: false
    t.timestamps null: false

    t.index ["email_log_id"]
    t.index ["status"]
    t.index ["analyzed_at"]
  end

  create_table "delivery_errors", force: :cascade do |t|
    t.bigint :email_log_id, null: false
    t.string :status_code, null: false
    t.string :status_description, null: true
    t.string :smtp_message, null: true
    t.string :recipient_domain, null: true
    t.integer :campaign_id, null: true
    t.integer :bounce_count, null: false, default: 0
    t.boolean :is_critical, null: false, default: false
    t.datetime :occurred_at, null: false
    t.timestamps null: false

    t.index ["email_log_id"]
    t.index ["campaign_id"]
    t.index ["occurred_at"]
    t.index ["is_critical"]
  end

  create_table "mailing_rules", force: :cascade do |t|
    t.string :rule_name, null: false, default: 'BounceThresholdRule'
    t.boolean :active, null: false, default: true
    t.integer :bounce_threshold, null: false, default: 10
    t.integer :bounce_threshold_window_minutes, null: false, default: 60
    t.integer :bounce_rate_threshold, null: false, default: 5
    t.string :stop_mailing_categories, null: true
    t.timestamps null: false
  end

  create_table "system_configs", force: :cascade do |t|
    t.string :key, null: false
    t.text :value, null: false
    t.text :encrypted_value, null: true
    t.timestamps null: false

    t.index ["key"]
    t.unique ["key"]
  end

  create_table "unsubscribes", force: :cascade do |t|
    t.bigint :email_log_id, null: false
    t.string :email, null: false
    t.string :reason, null: true
    t.string :ip_address, null: true
    t.string :user_agent, null: true
    t.datetime :unsubscribed_at, null: false
    t.timestamps null: false

    t.index ["email_log_id"]
  end

  create_table "bounced_emails", force: :cascade do |t|
    t.bigint :email_log_id, null: false
    t.string :bounce_type, null: true
    t.string :bounce_category, null: true
    t.string :smtp_code, null: true
    t.string :smtp_message, null: true
    t.integer :bounce_count, null: false, default: 1
    t.datetime :first_bounced_at, null: false
    t.datetime :last_bounced_at, null: false
    t.string :blocked_reason, null: true
    t.timestamps null: false

    t.index ["email_log_id"]
    t.index ["bounce_category"]
    t.index ["first_bounced_at"]
  end

  create_table "email_clicks", force: :cascade do |t|
    t.bigint :email_log_id, null: false
    t.string :url, null: false
    t.string :token, null: true
    t.string :ip_address, null: true
    t.boolean :null_ip, null: false, default: true
    t.datetime :clicked_at, null: false
    t.timestamps null: false

    t.index ["email_log_id"]
    t.index ["url"]
    t.index ["token"]
    t.index ["clicked_at"]
    t.index ["ip_address"]
    t.index ["email_log_id", "url"]
    t.index ["email_log_id", "clicked_at"]
  end

  create_table "email_opens", force: :cascade do |t|
    t.bigint :email_log_id, null: false
    t.string :token, null: true
    t.string :ip_address, null: true
    t.boolean :null_ip, null: false, default: true
    t.datetime :opened_at, null: false
    t.timestamps null: false

    t.index ["email_log_id"]
    t.index ["token"]
    t.index ["opened_at"]
    t.index ["ip_address"]
    t.index ["email_log_id", "opened_at"]
  end

  create_table "tracking_settings", force: :cascade do |t|
    t.boolean :track_clicks, null: false, default: true
    t.boolean :track_opens, null: false, default: true
    t.text :click_tracking_domain, null: true
    t.text :open_tracking_domain, null: true
    t.boolean :allow_ip_in_tracking, null: false, default: true
    t.timestamps null: false
  end
end
