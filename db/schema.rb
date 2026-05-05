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

ActiveRecord::Schema[8.1].define(version: 2026_05_04_000010) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "auth_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.inet "ip_address"
    t.string "kind", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "user_agent", limit: 255
    t.uuid "user_id"
    t.index ["created_at"], name: "index_auth_events_on_created_at"
    t.index ["kind"], name: "index_auth_events_on_kind"
    t.index ["user_id", "created_at"], name: "index_auth_events_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_auth_events_on_user_id"
  end

  create_table "auth_sessions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.inet "ip_address"
    t.datetime "last_used_at"
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent", limit: 255
    t.uuid "user_id", null: false
    t.index ["expires_at"], name: "index_auth_sessions_on_expires_at"
    t.index ["token_digest"], name: "index_auth_sessions_on_token_digest", unique: true
    t.index ["user_id"], name: "index_auth_sessions_on_user_id"
  end

  create_table "magic_link_tokens", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "purpose", null: false
    t.inet "requested_ip"
    t.string "token_digest", null: false
    t.uuid "user_id", null: false
    t.index ["expires_at"], name: "index_magic_link_tokens_on_expires_at"
    t.index ["token_digest"], name: "index_magic_link_tokens_on_token_digest", unique: true
    t.index ["user_id"], name: "index_magic_link_tokens_on_user_id"
  end

  create_table "passkey_credentials", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "external_id", null: false
    t.datetime "last_used_at"
    t.string "nickname", limit: 80, null: false
    t.text "public_key", null: false
    t.bigint "sign_count", default: 0, null: false
    t.string "transports", default: [], array: true
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["external_id"], name: "index_passkey_credentials_on_external_id", unique: true
    t.index ["user_id"], name: "index_passkey_credentials_on_user_id"
  end

  create_table "sop_callbacks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "callback_path", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.uuid "instance_id", null: false
    t.jsonb "response", default: {}
    t.string "status", default: "pending", null: false
    t.string "step_id", null: false
    t.datetime "updated_at", null: false
    t.index ["callback_path"], name: "index_sop_callbacks_on_callback_path", unique: true
    t.index ["expires_at"], name: "index_sop_callbacks_on_expires_at"
    t.index ["instance_id"], name: "index_sop_callbacks_on_instance_id"
    t.index ["status"], name: "index_sop_callbacks_on_status"
  end

  create_table "sop_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "actor"
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}
    t.string "event_type", null: false
    t.uuid "instance_id", null: false
    t.string "step_id"
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_sop_events_on_created_at"
    t.index ["event_type"], name: "index_sop_events_on_event_type"
    t.index ["instance_id"], name: "index_sop_events_on_instance_id"
  end

  create_table "sop_instances", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "error"
    t.jsonb "inputs", default: {}
    t.jsonb "metadata", default: {}
    t.jsonb "outputs", default: {}
    t.uuid "process_id"
    t.string "process_name", null: false
    t.string "process_version", null: false
    t.datetime "started_at"
    t.string "state", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["process_id"], name: "index_sop_instances_on_process_id"
    t.index ["process_name", "state"], name: "index_sop_instances_on_process_name_and_state"
    t.index ["started_at"], name: "index_sop_instances_on_started_at"
    t.index ["state"], name: "index_sop_instances_on_state"
  end

  create_table "sop_llm_calls", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "attempt", default: 1, null: false
    t.integer "cost_cents"
    t.datetime "created_at", null: false
    t.text "error"
    t.datetime "finished_at"
    t.integer "input_tokens"
    t.string "model", null: false
    t.integer "output_tokens"
    t.string "prompt_hash", null: false
    t.jsonb "request_payload", default: {}
    t.jsonb "response_payload", default: {}
    t.datetime "started_at", null: false
    t.string "status", null: false
    t.uuid "step_id", null: false
    t.datetime "updated_at", null: false
    t.index ["status"], name: "index_sop_llm_calls_on_status"
    t.index ["step_id", "attempt"], name: "index_sop_llm_calls_on_step_id_and_attempt", unique: true
    t.index ["step_id"], name: "index_sop_llm_calls_on_step_id"
  end

  create_table "sop_processes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "definition", default: {}, null: false
    t.text "description"
    t.string "name", null: false
    t.string "owner"
    t.string "status", default: "active", null: false
    t.string "tags", default: [], array: true
    t.datetime "updated_at", null: false
    t.string "version", null: false
    t.index ["name", "version"], name: "index_sop_processes_on_name_and_version", unique: true
    t.index ["status"], name: "index_sop_processes_on_status"
    t.index ["tags"], name: "index_sop_processes_on_tags", using: :gin
  end

  create_table "sop_schedules", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "cron_expression", null: false
    t.text "description"
    t.boolean "enabled", default: true, null: false
    t.integer "failure_count", default: 0, null: false
    t.jsonb "inputs", default: {}, null: false
    t.uuid "last_instance_id"
    t.datetime "last_run_at"
    t.string "last_status"
    t.string "name", null: false
    t.datetime "next_run_at"
    t.string "process_name", null: false
    t.string "timezone", default: "UTC", null: false
    t.datetime "updated_at", null: false
    t.index ["enabled", "next_run_at"], name: "index_sop_schedules_on_enabled_and_next_run_at"
    t.index ["process_name"], name: "index_sop_schedules_on_process_name"
  end

  create_table "sop_step_iterations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.datetime "finished_at"
    t.integer "index", null: false
    t.jsonb "iteration_inputs", default: {}
    t.jsonb "outputs", default: {}
    t.uuid "parent_step_id", null: false
    t.datetime "started_at", null: false
    t.string "state", default: "running", null: false
    t.datetime "updated_at", null: false
    t.index ["parent_step_id", "index"], name: "index_sop_step_iterations_on_parent_step_id_and_index", unique: true
    t.index ["parent_step_id"], name: "index_sop_step_iterations_on_parent_step_id"
  end

  create_table "sop_steps", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "attempt", default: 1, null: false
    t.datetime "completed_at"
    t.float "confidence"
    t.datetime "created_at", null: false
    t.string "decided_by"
    t.text "error"
    t.jsonb "inputs", default: {}
    t.uuid "instance_id", null: false
    t.jsonb "outputs", default: {}
    t.uuid "parent_iteration_id"
    t.integer "position", null: false
    t.datetime "started_at"
    t.string "state", default: "pending", null: false
    t.string "step_id", null: false
    t.string "step_name", null: false
    t.string "step_type", null: false
    t.string "sub_state"
    t.jsonb "tools", default: []
    t.datetime "updated_at", null: false
    t.index ["instance_id", "position"], name: "index_sop_steps_on_instance_id_and_position"
    t.index ["instance_id", "step_id"], name: "index_sop_steps_on_instance_id_and_step_id", unique: true
    t.index ["instance_id"], name: "index_sop_steps_on_instance_id"
    t.index ["parent_iteration_id"], name: "index_sop_steps_on_parent_iteration_id"
    t.index ["state"], name: "index_sop_steps_on_state"
    t.index ["step_type"], name: "index_sop_steps_on_step_type"
    t.index ["tools"], name: "index_sop_steps_on_tools", using: :gin
  end

  create_table "sop_webhook_deliveries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.uuid "event_id"
    t.string "event_name", null: false
    t.uuid "instance_id"
    t.datetime "last_attempted_at"
    t.datetime "next_attempt_at"
    t.jsonb "request_headers", default: {}, null: false
    t.jsonb "request_payload", default: {}, null: false
    t.text "response_body"
    t.jsonb "response_headers"
    t.integer "response_status"
    t.string "status", default: "pending", null: false
    t.uuid "step_iteration_id"
    t.datetime "updated_at", null: false
    t.uuid "webhook_id", null: false
    t.index ["created_at"], name: "index_sop_webhook_deliveries_on_created_at"
    t.index ["event_id"], name: "index_sop_webhook_deliveries_on_event_id"
    t.index ["instance_id"], name: "index_sop_webhook_deliveries_on_instance_id"
    t.index ["status", "next_attempt_at"], name: "index_sop_webhook_deliveries_on_status_and_next_attempt_at"
    t.index ["step_iteration_id"], name: "index_sop_webhook_deliveries_on_step_iteration_id"
    t.index ["webhook_id", "created_at"], name: "index_sop_webhook_deliveries_on_webhook_id_and_created_at", order: { created_at: :desc }
    t.index ["webhook_id"], name: "index_sop_webhook_deliveries_on_webhook_id"
  end

  create_table "sop_webhooks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "critical", default: false, null: false
    t.text "description"
    t.boolean "enabled", default: true, null: false
    t.text "events", default: [], null: false, array: true
    t.jsonb "headers", default: {}, null: false
    t.string "name", limit: 100, null: false
    t.uuid "process_id", null: false
    t.string "secret", null: false
    t.text "step_ids", default: [], null: false, array: true
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["events"], name: "index_sop_webhooks_on_events", using: :gin
    t.index ["process_id", "enabled"], name: "index_sop_webhooks_on_process_id_and_enabled"
    t.index ["process_id"], name: "index_sop_webhooks_on_process_id"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "display_name", limit: 100
    t.citext "email", null: false
    t.datetime "last_signed_in_at"
    t.string "role", default: "admin", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "auth_events", "users"
  add_foreign_key "auth_sessions", "users"
  add_foreign_key "magic_link_tokens", "users"
  add_foreign_key "passkey_credentials", "users"
  add_foreign_key "sop_callbacks", "sop_instances", column: "instance_id"
  add_foreign_key "sop_events", "sop_instances", column: "instance_id"
  add_foreign_key "sop_instances", "sop_processes", column: "process_id"
  add_foreign_key "sop_llm_calls", "sop_steps", column: "step_id"
  add_foreign_key "sop_step_iterations", "sop_steps", column: "parent_step_id"
  add_foreign_key "sop_steps", "sop_instances", column: "instance_id"
  add_foreign_key "sop_webhook_deliveries", "sop_events", column: "event_id"
  add_foreign_key "sop_webhook_deliveries", "sop_instances", column: "instance_id"
  add_foreign_key "sop_webhook_deliveries", "sop_step_iterations", column: "step_iteration_id"
  add_foreign_key "sop_webhook_deliveries", "sop_webhooks", column: "webhook_id"
  add_foreign_key "sop_webhooks", "sop_processes", column: "process_id"
end
