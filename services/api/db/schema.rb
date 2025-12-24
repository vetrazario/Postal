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

ActiveRecord::Schema[7.1].define(version: 5) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "api_keys", force: :cascade do |t|
    t.string "key_hash", limit: 64, null: false
    t.string "name", null: false
    t.jsonb "permissions", default: {"send"=>true, "batch"=>true}, null: false
    t.integer "rate_limit", default: 100, null: false
    t.integer "daily_limit", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.datetime "last_used_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key_hash"], name: "idx_api_keys_active", where: "(active = true)"
    t.index ["key_hash"], name: "index_api_keys_on_key_hash", unique: true
    t.check_constraint "length(key_hash::text) = 64", name: "api_keys_key_hash_length"
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
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id"], name: "index_campaign_stats_on_campaign_id", unique: true
    t.check_constraint "total_sent >= 0 AND total_delivered >= 0 AND total_opened >= 0 AND total_clicked >= 0 AND total_bounced >= 0 AND total_complained >= 0 AND total_failed >= 0", name: "campaign_stats_positive"
  end

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
    t.datetime "sent_at", precision: nil
    t.datetime "delivered_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id", "status"], name: "idx_email_logs_campaign_status"
    t.index ["campaign_id"], name: "index_email_logs_on_campaign_id"
    t.index ["created_at"], name: "idx_email_logs_pending", where: "((status)::text = ANY ((ARRAY['queued'::character varying, 'processing'::character varying, 'sent'::character varying])::text[]))"
    t.index ["created_at"], name: "index_email_logs_on_created_at"
    t.index ["external_message_id"], name: "index_email_logs_on_external_message_id"
    t.index ["message_id"], name: "index_email_logs_on_message_id", unique: true
    t.index ["recipient"], name: "index_email_logs_on_recipient"
    t.index ["status"], name: "index_email_logs_on_status"
    t.index ["template_id"], name: "index_email_logs_on_template_id"
    t.check_constraint "status::text = ANY (ARRAY['queued'::character varying, 'processing'::character varying, 'sent'::character varying, 'delivered'::character varying, 'bounced'::character varying, 'failed'::character varying, 'complained'::character varying]::text[])", name: "email_logs_status_check"
  end

  create_table "email_templates", force: :cascade do |t|
    t.string "external_id", limit: 64, null: false
    t.string "name", null: false
    t.text "subject_template", null: false
    t.text "html_template", null: false
    t.jsonb "variables_schema", default: {}, null: false
    t.integer "version", default: 1, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["external_id"], name: "idx_templates_external_id", where: "(active = true)"
    t.index ["external_id"], name: "index_email_templates_on_external_id", unique: true
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
    t.check_constraint "event_type::text = ANY (ARRAY['open'::character varying, 'click'::character varying, 'bounce'::character varying, 'complaint'::character varying, 'delivered'::character varying]::text[])", name: "tracking_events_type_check"
  end

  add_foreign_key "email_logs", "email_templates", column: "template_id"
  add_foreign_key "tracking_events", "email_logs", name: "fk_tracking_events_email_logs", on_delete: :cascade
end
