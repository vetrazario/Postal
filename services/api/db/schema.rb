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
  enable_extension "uuid-ossp"

  create_table "api_keys", force: :cascade do |t|
    t.string "key_hash", null: false
    t.string "name", null: false
    t.boolean "active", default: true, null: false
    t.string "description"
    t.datetime "last_used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key_hash"], name: "index_api_keys_on_key_hash", unique: true
  end

  create_table "email_templates", force: :cascade do |t|
    t.string "name", null: false
    t.text "subject", null: false
    t.text "html_body", null: false
    t.text "text_body"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "email_logs", force: :cascade do |t|
    t.string "message_id", null: false
    t.string "external_message_id"
    t.string "recipient", null: false
    t.string "recipient_masked"
    t.string "sender"
    t.string "subject"
    t.text "html_body"
    t.string "status", null: false
    t.string "campaign_id"
    t.string "campaign_name"
    t.string "template_id"
    t.json "metadata"
    t.string "smtp_code"
    t.string "smtp_message"
    t.string "postal_message_id"
    t.string "bounce_type"
    t.string "bounce_category"
    t.string "bounce_reason"
    t.integer "click_count", default: 0, null: false
    t.integer "open_count", default: 0, null: false
    t.string "ip_address"
    t.string "user_agent"
    t.string "list_unsubscribe_url"
    t.json "tracking_data"
    t.json "status_details"
    t.datetime "sent_at"
    t.datetime "delivered_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id", "status"], name: "index_email_logs_on_campaign_id_and_status"
    t.index ["campaign_id"], name: "index_email_logs_on_campaign_id"
    t.index ["created_at"], name: "index_email_logs_on_created_at"
    t.index ["external_message_id"], name: "index_email_logs_on_external_message_id"
    t.index ["message_id"], name: "index_email_logs_on_message_id", unique: true
    t.index ["postal_message_id"], name: "index_email_logs_on_postal_message_id"
    t.index ["status"], name: "index_email_logs_on_status"
  end

  create_table "tracking_events", force: :cascade do |t|
    t.bigint "email_log_id", null: false
    t.string "event_type", null: false
    t.json "event_data"
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email_log_id"], name: "index_tracking_events_on_email_log_id"
    t.index ["event_type"], name: "index_tracking_events_on_event_type"
  end

  create_table "campaign_stats", force: :cascade do |t|
    t.string "campaign_id", null: false
    t.string "campaign_name"
    t.integer "sent", default: 0, null: false
    t.integer "delivered", default: 0, null: false
    t.integer "bounced", default: 0, null: false
    t.integer "failed", default: 0, null: false
    t.integer "queued", default: 0, null: false
    t.integer "complained", default: 0, null: false
    t.integer "opened", default: 0, null: false
    t.integer "clicked", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id"], name: "index_campaign_stats_on_campaign_id", unique: true
  end

  create_table "smtp_credentials", force: :cascade do |t|
    t.string "username", null: false
    t.string "password_encrypted", null: false
    t.boolean "active", default: true, null: false
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["username"], name: "index_smtp_credentials_on_username", unique: true
  end

  create_table "webhook_endpoints", force: :cascade do |t|
    t.string "url", null: false
    t.string "secret", null: false
    t.boolean "active", default: true, null: false
    t.string "description"
    t.json "headers"
    t.string "events", array: true, default: []
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "webhook_logs", force: :cascade do |t|
    t.bigint "webhook_endpoint_id", null: false
    t.string "event_type", null: false
    t.json "payload"
    t.integer "status_code"
    t.string "error_message"
    t.datetime "request_sent_at", null: false
    t.datetime "response_received_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_type"], name: "index_webhook_logs_on_event_type"
    t.index ["request_sent_at"], name: "index_webhook_logs_on_request_sent_at"
    t.index ["webhook_endpoint_id"], name: "index_webhook_logs_on_webhook_endpoint_id"
  end

  create_table "ai_settings", force: :cascade do |t|
    t.string "provider", default: "openai"
    t.string "model_name", default: "gpt-4"
    t.text "api_key_encrypted"
    t.boolean "enabled", default: false, null: false
    t.json "settings"
    t.decimal "total_estimated_cost", precision: 10, scale: 4, default: "0.0"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "ai_analyses", force: :cascade do |t|
    t.string "analysis_type", null: false
    t.string "campaign_id"
    t.json "input_data"
    t.json "result"
    t.string "status", default: "pending", null: false
    t.string "error_message"
    t.decimal "estimated_cost", precision: 10, scale: 4
    t.integer "tokens_used"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["analysis_type"], name: "index_ai_analyses_on_analysis_type"
    t.index ["campaign_id"], name: "index_ai_analyses_on_campaign_id"
    t.index ["status"], name: "index_ai_analyses_on_status"
  end

  create_table "delivery_errors", force: :cascade do |t|
    t.bigint "email_log_id"
    t.string "campaign_id", null: false
    t.string "category", null: false
    t.string "smtp_code"
    t.string "smtp_message"
    t.string "recipient_domain"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id", "created_at"], name: "index_delivery_errors_on_campaign_id_and_created_at"
    t.index ["campaign_id"], name: "index_delivery_errors_on_campaign_id"
    t.index ["category"], name: "index_delivery_errors_on_category"
    t.index ["email_log_id"], name: "index_delivery_errors_on_email_log_id"
  end

  create_table "mailing_rules", force: :cascade do |t|
    t.string "name", default: "Default Rule", null: false
    t.boolean "active", default: true
    t.integer "max_bounce_rate", default: 10
    t.integer "max_rate_limit_errors", default: 5
    t.integer "max_spam_blocks", default: 3
    t.integer "check_window_minutes", default: 60
    t.boolean "auto_stop_mailing", default: true
    t.string "notification_email"
    t.string "ams_api_url"
    t.text "ams_api_key_encrypted"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "system_configs", force: :cascade do |t|
    t.string "key", null: false
    t.text "value"
    t.text "encrypted_value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_system_configs_on_key", unique: true
  end

  create_table "unsubscribes", force: :cascade do |t|
    t.string "email", null: false
    t.string "campaign_id"
    t.string "reason"
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "unsubscribed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id"], name: "index_unsubscribes_on_campaign_id"
    t.index ["email", "campaign_id"], name: "index_unsubscribes_on_email_and_campaign_id", unique: true
    t.index ["email"], name: "index_unsubscribes_on_email"
  end

  create_table "bounced_emails", force: :cascade do |t|
    t.string "email", null: false
    t.string "campaign_id"
    t.string "bounce_type", null: false
    t.string "bounce_category"
    t.string "smtp_code"
    t.string "smtp_message"
    t.integer "bounce_count", default: 1, null: false
    t.datetime "first_bounced_at", null: false
    t.datetime "last_bounced_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bounce_category"], name: "index_bounced_emails_on_bounce_category"
    t.index ["bounce_type"], name: "index_bounced_emails_on_bounce_type"
    t.index ["email", "campaign_id"], name: "index_bounced_emails_on_email_and_campaign_id", unique: true
    t.index ["email"], name: "index_bounced_emails_on_email"
    t.index ["last_bounced_at"], name: "index_bounced_emails_on_last_bounced_at"
  end

  create_table "email_clicks", force: :cascade do |t|
    t.bigint "email_log_id", null: false
    t.string "campaign_id", null: false
    t.string "url", null: false
    t.string "token", null: false
    t.string "ip_address"
    t.string "user_agent"
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
    t.string "token", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "opened_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id", "opened_at"], name: "index_email_opens_on_campaign_id_and_opened_at"
    t.index ["email_log_id"], name: "index_email_opens_on_email_log_id"
    t.index ["token"], name: "index_email_opens_on_token", unique: true
  end

  create_table "tracking_settings", force: :cascade do |t|
    t.boolean "track_clicks", default: true, null: false
    t.boolean "track_opens", default: true, null: false
    t.string "tracking_domain"
    t.boolean "add_footer", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "tracking_events", "email_logs"
  add_foreign_key "webhook_logs", "webhook_endpoints"
  add_foreign_key "delivery_errors", "email_logs"
  add_foreign_key "email_clicks", "email_logs"
  add_foreign_key "email_opens", "email_logs"
end
