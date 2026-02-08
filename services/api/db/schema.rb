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

ActiveRecord::Schema[7.1].define(version: 2026_02_08_000001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

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
    t.index ["key_hash"], name: "idx_api_keys_active", where: "(active = true)"
    t.index ["key_hash"], name: "index_api_keys_on_key_hash", unique: true
  end

  create_table "email_templates", force: :cascade do |t|
    t.string "external_id", limit: 64, null: false
    t.string "name", limit: 255, null: false
    t.text "html_content", null: false
    t.text "plain_content"
    t.jsonb "variables", default: []
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_email_templates_on_active"
    t.index ["external_id"], name: "index_email_templates_on_external_id", unique: true
  end

  create_table "email_logs", force: :cascade do |t|
    t.string "message_id", limit: 64, null: false
    t.string "external_message_id", limit: 64
    t.string "campaign_id", limit: 64
    t.bigint "template_id"
    t.string "recipient", limit: 255, null: false
    t.string "recipient_masked", limit: 255, null: false
    t.string "sender", limit: 255, null: false
    t.string "subject", limit: 500, null: false
    t.string "postal_message_id", limit: 255
    t.string "status", limit: 20, default: "queued", null: false
    t.jsonb "status_details"
    t.string "bounce_category", limit: 30
    t.string "smtp_code", limit: 10
    t.text "smtp_message"
    t.datetime "sent_at"
    t.datetime "delivered_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id", "bounce_category"], name: "idx_email_logs_campaign_bounce_category", where: "bounce_category IS NOT NULL"
    t.index ["campaign_id", "status"], name: "idx_email_logs_campaign_status"
    t.index ["campaign_id"], name: "index_email_logs_on_campaign_id"
    t.index ["created_at"], name: "idx_email_logs_pending", where: "(status IN ('queued', 'processing', 'sent'))"
    t.index ["created_at"], name: "index_email_logs_on_created_at"
    t.index ["external_message_id"], name: "index_email_logs_on_external_message_id"
    t.index ["message_id"], name: "index_email_logs_on_message_id", unique: true
    t.index ["recipient"], name: "index_email_logs_on_recipient"
    t.index ["status"], name: "index_email_logs_on_status"
  end

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
    t.integer "total_unsubscribed", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id"], name: "index_campaign_stats_on_campaign_id", unique: true
  end

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

  create_table "webhook_endpoints", force: :cascade do |t|
    t.string "url", null: false
    t.string "secret_key"
    t.boolean "active", default: true, null: false
    t.json "events", default: ["delivered", "opened", "clicked", "bounced", "failed", "complained"]
    t.integer "retry_count", default: 3, null: false
    t.integer "timeout", default: 30, null: false, comment: "Timeout in seconds"
    t.integer "successful_deliveries", default: 0, null: false
    t.integer "failed_deliveries", default: 0, null: false
    t.datetime "last_success_at"
    t.datetime "last_failure_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_webhook_endpoints_on_active"
    t.index ["url"], name: "index_webhook_endpoints_on_url"
  end

  create_table "webhook_logs", force: :cascade do |t|
    t.bigint "webhook_endpoint_id", null: false
    t.string "event_type", null: false
    t.string "message_id"
    t.integer "response_code"
    t.text "response_body"
    t.boolean "success", default: false, null: false
    t.datetime "delivered_at"
    t.float "duration_ms", comment: "Request duration in milliseconds"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_webhook_logs_on_created_at"
    t.index ["event_type"], name: "index_webhook_logs_on_event_type"
    t.index ["message_id"], name: "index_webhook_logs_on_message_id"
    t.index ["success"], name: "index_webhook_logs_on_success"
    t.index ["webhook_endpoint_id", "created_at"], name: "index_webhook_logs_on_webhook_endpoint_id_and_created_at"
    t.index ["webhook_endpoint_id"], name: "index_webhook_logs_on_webhook_endpoint_id"
  end

  create_table "ai_settings", id: :integer, default: 1, force: :cascade do |t|
    t.string "openrouter_api_key"
    t.string "ai_model", default: "anthropic/claude-3.5-sonnet", null: false
    t.float "temperature", default: 0.7, null: false
    t.integer "max_tokens", default: 4000, null: false
    t.boolean "enabled", default: false, null: false
    t.integer "total_analyses", default: 0, null: false
    t.integer "total_tokens_used", default: 0, null: false
    t.datetime "last_analysis_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "ai_analyses", force: :cascade do |t|
    t.string "analysis_type", null: false, comment: "bounce_analysis, time_optimization, campaign_comparison"
    t.string "campaign_id", comment: "Associated campaign ID if applicable"
    t.json "analysis_result", comment: "JSON result from AI analysis"
    t.integer "prompt_tokens", default: 0, null: false
    t.integer "completion_tokens", default: 0, null: false
    t.integer "total_tokens", default: 0, null: false
    t.string "model_used"
    t.string "status", default: "completed", null: false, comment: "processing, completed, failed"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["analysis_type", "created_at"], name: "index_ai_analyses_on_analysis_type_and_created_at"
    t.index ["analysis_type"], name: "index_ai_analyses_on_analysis_type"
    t.index ["created_at"], name: "index_ai_analyses_on_created_at"
    t.index ["status"], name: "index_ai_analyses_on_status"
  end

  create_table "delivery_errors", force: :cascade do |t|
    t.bigint "email_log_id", null: false
    t.string "campaign_id", limit: 64, null: false
    t.string "category", limit: 30, null: false
    t.string "smtp_code", limit: 10
    t.text "smtp_message"
    t.string "recipient_domain", limit: 255
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id", "category", "created_at"], name: "idx_delivery_errors_campaign_category_created"
    t.index ["category", "created_at"], name: "idx_delivery_errors_category_created"
    t.index ["email_log_id"], name: "index_delivery_errors_on_email_log_id"
  end

  create_table "mailing_rules", force: :cascade do |t|
    t.string "name", default: "Default Rule", null: false
    t.boolean "active", default: true
    t.integer "max_bounce_rate", default: 10
    t.integer "max_rate_limit_errors", default: 5
    t.integer "max_spam_blocks", default: 3
    t.integer "max_user_not_found_errors", default: 3
    t.integer "check_window_minutes", default: 60
    t.boolean "auto_stop_mailing", default: true
    t.boolean "notify_email", default: false
    t.string "notification_email"
    t.string "ams_api_url"
    t.text "ams_api_key_encrypted"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "system_configs", force: :cascade do |t|
    t.string "domain", null: false
    t.string "allowed_sender_domains"
    t.string "cors_origins"
    t.string "ams_callback_url"
    t.text "ams_api_key_encrypted"
    t.string "ams_api_url"
    t.string "postal_api_url", default: "http://postal:5000"
    t.text "postal_api_key_encrypted"
    t.text "postal_signing_key_encrypted"
    t.integer "daily_limit", default: 50000
    t.integer "sidekiq_concurrency", default: 5
    t.text "webhook_secret_encrypted"
    t.jsonb "changed_fields", default: {}
    t.boolean "restart_required", default: false
    t.string "restart_services", default: [], array: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    # Tracking settings (from migration 20260114180200)
    t.boolean "enable_open_tracking", default: false
    t.boolean "enable_click_tracking", default: true
    t.string "tracking_domain"
    t.boolean "use_utm_tracking", default: true
    t.integer "max_tracked_links", default: 5
    t.boolean "tracking_footer_enabled", default: true
    t.integer "daily_send_limit", default: 500
    t.boolean "warmup_mode", default: false
    # SMTP Relay settings (from migration 020, partially removed by 022)
    t.integer "smtp_relay_port", default: 2587
    t.boolean "smtp_relay_auth_required", default: true
    t.boolean "smtp_relay_tls_enabled", default: true
    # From migration 021
    t.text "postal_webhook_public_key_encrypted"
    t.string "sidekiq_web_username"
    t.text "sidekiq_web_password_encrypted"
    t.string "log_level", default: "info"
    t.string "sentry_dsn"
    t.string "letsencrypt_email"
    t.index ["id"], name: "index_system_configs_on_id", unique: true
  end

  create_table "unsubscribes", force: :cascade do |t|
    t.string "email", limit: 255, null: false
    t.string "campaign_id", limit: 64
    t.string "reason", limit: 50, default: "user_request"
    t.inet "ip_address"
    t.text "user_agent"
    t.datetime "unsubscribed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id"], name: "idx_unsubscribes_campaign"
    t.index ["email", "campaign_id"], name: "idx_unsubscribes_email_campaign", unique: true
    t.index ["email"], name: "idx_unsubscribes_email"
    t.index ["unsubscribed_at"], name: "idx_unsubscribes_unsubscribed_at"
  end

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

  create_table "email_clicks", force: :cascade do |t|
    t.bigint "email_log_id", null: false
    t.string "campaign_id", null: false
    t.string "url", limit: 2048, null: false
    t.string "ip_address"
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

  create_table "email_opens", force: :cascade do |t|
    t.bigint "email_log_id", null: false
    t.string "campaign_id", null: false
    t.string "ip_address"
    t.string "user_agent", limit: 1024
    t.string "token", null: false
    t.datetime "opened_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id", "opened_at"], name: "index_email_opens_on_campaign_id_and_opened_at"
    t.index ["email_log_id"], name: "index_email_opens_on_email_log_id"
    t.index ["token"], name: "index_email_opens_on_token", unique: true
  end

  add_foreign_key "delivery_errors", "email_logs", on_delete: :cascade
  add_foreign_key "email_clicks", "email_logs"
  add_foreign_key "email_logs", "email_templates", column: "template_id"
  add_foreign_key "email_opens", "email_logs"
  add_foreign_key "tracking_events", "email_logs", on_delete: :cascade
  add_foreign_key "webhook_logs", "webhook_endpoints"
end
