# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_01_19_000001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  # ===========================================
  # API Keys
  # ===========================================
  create_table "api_keys", force: :cascade do |t|
    t.string "key_hash", limit: 64, null: false
    t.string "name", null: false
    t.jsonb "permissions", default: {"send"=>true, "batch"=>true}, null: false
    t.integer "rate_limit", default: 100, null: false
    t.integer "daily_limit", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.datetime "last_used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key_hash"], name: "index_api_keys_on_key_hash", unique: true
    t.index ["key_hash"], name: "idx_api_keys_active", where: "(active = true)"
  end

  # ===========================================
  # Email Templates
  # ===========================================
  create_table "email_templates", force: :cascade do |t|
    t.string "name", null: false
    t.string "external_id", limit: 64
    t.text "subject", null: false
    t.text "html_body", null: false
    t.text "text_body"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["external_id"], name: "index_email_templates_on_external_id", unique: true
    t.index ["name"], name: "index_email_templates_on_name"
  end

  # ===========================================
  # Email Logs
  # ===========================================
  create_table "email_logs", force: :cascade do |t|
    t.string "message_id", limit: 64, null: false
    t.string "external_message_id", limit: 64, null: false
    t.string "campaign_id", limit: 64, null: false
    t.bigint "template_id"
    t.string "recipient", limit: 255, null: false
    t.string "recipient_masked", limit: 255, null: false
    t.string "sender", limit: 255, null: false
    t.string "subject", limit: 500, null: false
    t.string "postal_message_id", limit: 255
    t.string "status", limit: 20, default: "queued", null: false
    t.jsonb "status_details"
    t.datetime "sent_at"
    t.datetime "delivered_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id", "status"], name: "idx_email_logs_campaign_status"
    t.index ["campaign_id"], name: "index_email_logs_on_campaign_id"
    t.index ["created_at"], name: "idx_email_logs_pending", where: "(status IN ('queued', 'processing', 'sent'))"
    t.index ["created_at"], name: "index_email_logs_on_created_at"
    t.index ["external_message_id"], name: "index_email_logs_on_external_message_id"
    t.index ["message_id"], name: "index_email_logs_on_message_id", unique: true
    t.index ["recipient"], name: "index_email_logs_on_recipient"
    t.index ["status"], name: "index_email_logs_on_status"
    t.index ["template_id"], name: "index_email_logs_on_template_id"
  end

  # ===========================================
  # Tracking Events
  # ===========================================
  create_table "tracking_events", force: :cascade do |t|
    t.bigint "email_log_id", null: false
    t.string "event_type", limit: 20, null: false
    t.jsonb "event_data"
    t.inet "ip_address"
    t.text "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_tracking_events_on_created_at"
    t.index ["email_log_id"], name: "index_tracking_events_on_email_log_id"
    t.index ["event_type", "created_at"], name: "idx_tracking_type_created"
    t.index ["event_type"], name: "index_tracking_events_on_event_type"
  end

  # ===========================================
  # Campaign Stats
  # ===========================================
  create_table "campaign_stats", force: :cascade do |t|
    t.string "campaign_id", limit: 64, null: false
    t.integer "total_sent", default: 0, null: false
    t.integer "total_delivered", default: 0, null: false
    t.integer "total_opened", default: 0, null: false
    t.integer "total_clicked", default: 0, null: false
    t.integer "total_bounced", default: 0, null: false
    t.integer "total_complained", default: 0, null: false
    t.integer "total_failed", default: 0, null: false
    t.integer "unique_opened", default: 0, null: false
    t.integer "unique_clicked", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id"], name: "index_campaign_stats_on_campaign_id", unique: true
  end

  # ===========================================
  # SMTP Credentials
  # ===========================================
  create_table "smtp_credentials", force: :cascade do |t|
    t.string "username", null: false
    t.string "password_hash", null: false
    t.string "description"
    t.boolean "active", default: true, null: false
    t.integer "rate_limit", default: 100, null: false, comment: "Emails per hour"
    t.datetime "last_used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_smtp_credentials_on_active"
    t.index ["last_used_at"], name: "index_smtp_credentials_on_last_used_at"
    t.index ["username"], name: "index_smtp_credentials_on_username", unique: true
  end

  # ===========================================
  # Webhook Endpoints
  # ===========================================
  create_table "webhook_endpoints", force: :cascade do |t|
    t.string "url", null: false
    t.string "secret", null: false
    t.boolean "active", default: true, null: false
    t.string "description"
    t.jsonb "events", default: []
    t.jsonb "headers", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_webhook_endpoints_on_active"
  end

  # ===========================================
  # Webhook Logs
  # ===========================================
  create_table "webhook_logs", force: :cascade do |t|
    t.bigint "webhook_endpoint_id", null: false
    t.string "event_type", null: false
    t.jsonb "payload"
    t.integer "status_code"
    t.text "response_body"
    t.string "error_message"
    t.integer "retry_count", default: 0
    t.datetime "sent_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_type"], name: "index_webhook_logs_on_event_type"
    t.index ["sent_at"], name: "index_webhook_logs_on_sent_at"
    t.index ["webhook_endpoint_id"], name: "index_webhook_logs_on_webhook_endpoint_id"
  end

  # ===========================================
  # AI Settings
  # ===========================================
  create_table "ai_settings", force: :cascade do |t|
    t.string "provider", null: false
    t.string "model", null: false
    t.text "api_key_encrypted"
    t.boolean "enabled", default: false, null: false
    t.jsonb "settings", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  # ===========================================
  # AI Analyses
  # ===========================================
  create_table "ai_analyses", force: :cascade do |t|
    t.bigint "email_log_id"
    t.string "analysis_type", null: false
    t.string "provider", null: false
    t.string "model", null: false
    t.text "prompt"
    t.text "result"
    t.jsonb "metadata", default: {}
    t.string "status", default: "pending", null: false
    t.datetime "analyzed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["analysis_type"], name: "index_ai_analyses_on_analysis_type"
    t.index ["analyzed_at"], name: "index_ai_analyses_on_analyzed_at"
    t.index ["email_log_id"], name: "index_ai_analyses_on_email_log_id"
    t.index ["status"], name: "index_ai_analyses_on_status"
  end

  # ===========================================
  # Delivery Errors
  # ===========================================
  create_table "delivery_errors", force: :cascade do |t|
    t.bigint "email_log_id", null: false
    t.string "error_type", null: false
    t.string "error_code"
    t.text "error_message"
    t.string "recipient_domain"
    t.jsonb "details", default: {}
    t.datetime "occurred_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email_log_id"], name: "index_delivery_errors_on_email_log_id"
    t.index ["error_type"], name: "index_delivery_errors_on_error_type"
    t.index ["occurred_at"], name: "index_delivery_errors_on_occurred_at"
  end

  # ===========================================
  # Mailing Rules
  # ===========================================
  create_table "mailing_rules", force: :cascade do |t|
    t.string "name", null: false
    t.string "rule_type", null: false
    t.jsonb "conditions", default: {}
    t.jsonb "actions", default: {}
    t.boolean "active", default: true, null: false
    t.integer "priority", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_mailing_rules_on_active"
    t.index ["rule_type"], name: "index_mailing_rules_on_rule_type"
  end

  # ===========================================
  # System Configs (Singleton)
  # ===========================================
  create_table "system_configs", force: :cascade do |t|
    # Server Configuration
    t.string "domain", null: false
    t.string "allowed_sender_domains"
    t.string "cors_origins"

    # AMS Integration
    t.string "ams_callback_url"
    t.text "ams_api_key_encrypted"
    t.string "ams_api_url"

    # Postal Configuration
    t.string "postal_api_url", default: "http://postal:5000"
    t.text "postal_api_key_encrypted"
    t.text "postal_signing_key_encrypted"
    t.text "postal_webhook_public_key_encrypted"

    # Limits & Security
    t.integer "daily_limit", default: 50000
    t.integer "sidekiq_concurrency", default: 5
    t.text "webhook_secret_encrypted"

    # SMTP Relay settings
    t.text "smtp_relay_secret_encrypted"
    t.integer "smtp_relay_port", default: 2587
    t.boolean "smtp_relay_auth_required", default: true
    t.boolean "smtp_relay_tls_enabled", default: true

    # Sidekiq Web UI
    t.string "sidekiq_web_username"
    t.text "sidekiq_web_password_encrypted"

    # Logging
    t.string "log_level", default: "info"
    t.string "sentry_dsn"

    # Let's Encrypt
    t.string "letsencrypt_email"

    # Tracking settings
    t.boolean "enable_click_tracking", default: true
    t.boolean "enable_open_tracking", default: true
    t.integer "max_tracked_links", default: 50
    t.string "tracking_domain"
    t.boolean "tracking_footer_enabled", default: false

    # Metadata for tracking changes
    t.jsonb "changed_fields", default: {}
    t.boolean "restart_required", default: false
    t.string "restart_services", array: true, default: []

    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  # ===========================================
  # Unsubscribes
  # ===========================================
  create_table "unsubscribes", force: :cascade do |t|
    t.string "email", null: false
    t.string "campaign_id"
    t.string "reason"
    t.inet "ip_address"
    t.text "user_agent"
    t.datetime "unsubscribed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id"], name: "index_unsubscribes_on_campaign_id"
    t.index ["email", "campaign_id"], name: "index_unsubscribes_on_email_and_campaign_id", unique: true
    t.index ["email"], name: "index_unsubscribes_on_email"
  end

  # ===========================================
  # Bounced Emails
  # ===========================================
  create_table "bounced_emails", force: :cascade do |t|
    t.string "email", limit: 255, null: false
    t.string "bounce_type", limit: 10, null: false
    t.string "bounce_category", limit: 30
    t.string "smtp_code", limit: 10
    t.text "smtp_message"
    t.string "campaign_id", limit: 64
    t.integer "bounce_count", default: 1, null: false
    t.datetime "first_bounced_at", null: false
    t.datetime "last_bounced_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bounce_type"], name: "idx_bounced_emails_bounce_type"
    t.index ["campaign_id"], name: "idx_bounced_emails_campaign"
    t.index ["email", "campaign_id"], name: "idx_bounced_emails_email_campaign", unique: true
    t.index ["email"], name: "idx_bounced_emails_email"
    t.index ["last_bounced_at"], name: "idx_bounced_emails_last_bounced_at"
  end

  # ===========================================
  # Email Clicks (Tracking)
  # ===========================================
  create_table "email_clicks", force: :cascade do |t|
    t.bigint "email_log_id", null: false
    t.string "campaign_id", null: false
    t.string "url", limit: 2048, null: false
    t.inet "ip_address"
    t.string "user_agent", limit: 1024
    t.string "token", null: false
    t.datetime "clicked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id", "clicked_at"], name: "index_email_clicks_on_campaign_id_and_clicked_at"
    t.index ["email_log_id", "url"], name: "index_email_clicks_on_email_log_id_and_url"
    t.index ["email_log_id"], name: "index_email_clicks_on_email_log_id"
    t.index ["token"], name: "index_email_clicks_on_token", unique: true
  end

  # ===========================================
  # Email Opens (Tracking)
  # ===========================================
  create_table "email_opens", force: :cascade do |t|
    t.bigint "email_log_id", null: false
    t.string "campaign_id", null: false
    t.inet "ip_address"
    t.string "user_agent", limit: 1024
    t.string "token", null: false
    t.datetime "opened_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id", "opened_at"], name: "index_email_opens_on_campaign_id_and_opened_at"
    t.index ["email_log_id"], name: "index_email_opens_on_email_log_id"
    t.index ["token"], name: "index_email_opens_on_token", unique: true
  end

  # ===========================================
  # Foreign Keys
  # ===========================================
  add_foreign_key "ai_analyses", "email_logs"
  add_foreign_key "delivery_errors", "email_logs"
  add_foreign_key "email_clicks", "email_logs"
  add_foreign_key "email_logs", "email_templates", column: "template_id"
  add_foreign_key "email_opens", "email_logs"
  add_foreign_key "tracking_events", "email_logs", on_delete: :cascade
  add_foreign_key "webhook_logs", "webhook_endpoints"
end
