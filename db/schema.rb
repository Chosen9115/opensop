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

ActiveRecord::Schema[8.1].define(version: 2026_04_18_000006) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

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
    t.integer "position", null: false
    t.datetime "started_at"
    t.string "state", default: "pending", null: false
    t.string "step_id", null: false
    t.string "step_name", null: false
    t.string "step_type", null: false
    t.string "sub_state"
    t.datetime "updated_at", null: false
    t.index ["instance_id", "position"], name: "index_sop_steps_on_instance_id_and_position"
    t.index ["instance_id", "step_id"], name: "index_sop_steps_on_instance_id_and_step_id", unique: true
    t.index ["instance_id"], name: "index_sop_steps_on_instance_id"
    t.index ["state"], name: "index_sop_steps_on_state"
    t.index ["step_type"], name: "index_sop_steps_on_step_type"
  end

  add_foreign_key "sop_callbacks", "sop_instances", column: "instance_id"
  add_foreign_key "sop_events", "sop_instances", column: "instance_id"
  add_foreign_key "sop_instances", "sop_processes", column: "process_id"
  add_foreign_key "sop_steps", "sop_instances", column: "instance_id"
end
