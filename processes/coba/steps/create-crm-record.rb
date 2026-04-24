#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# Force UTF-8 for all IO. launchd spawns this script with LANG/LC_CTYPE
# unset and Ruby defaults to US-ASCII, which blows up the moment a
# lead_message or company name contains any UTF-8 character (em-dash,
# accented letters, etc.). Set explicitly here so the encoding posture
# doesn't depend on who invoked us (Fly engine vs. launchd-spawned bridge).
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8
[STDIN, STDOUT, STDERR].each { |io| io.set_encoding(Encoding::UTF_8) rescue nil }

# PRIVATE — Coba fork only. Contains DenchClaw-specific IDs and defaults.
#
# Inserts a lead into DenchClaw as BOTH:
#
#   1. A `people` entry (the contact: Full Name, Email, Phone, Company,
#      Job Title, Status=Lead).
#   2. A `deal` entry (the pipeline record: Name, Stage=Inbound,
#      Business Model=Banking, Funnel=Coba Pipeline, Channel=<source>,
#      Contact fields, Primary Contact → the people entry above).
#
# Idempotent on email: if a person already exists with the same email,
# returns their IDs and skips creation. (Prevents duplicate CRM records
# from retry traffic — see GAPS.md replay protection note.)
#
# Protocol: reads JSON inputs from stdin, writes JSON outputs to stdout.
# Shells out to the `duckdb` CLI rather than adding the `duckdb` gem as
# a dependency.

require "csv"
require "json"
require "open3"
require "securerandom"

DB_PATH = "/Users/c/Documents/coba-twin/data/denchclaw/workspace/workspace.duckdb"

# ── DenchClaw object + field IDs ──────────────────────────────────────
OBJ_PEOPLE = "seed_obj_people_00000000000000"
OBJ_DEAL   = "1100afdf-2dfc-4e8d-b33f-7359f1d69c75"

FLD_PEOPLE = {
  full_name:  "seed_fld_people_fullname_000000",
  email:      "seed_fld_people_email_000000000",
  phone:      "seed_fld_people_phone_000000000",
  company:    "seed_fld_people_company_0000000",
  status:     "seed_fld_people_status_00000000",
  job_title:  "a22c16a5-672e-4fa0-8b1d-aaaf357b72a3"
}.freeze

FLD_DEAL = {
  name:              "957f70dd-912b-461f-a248-c717ac70bd43",
  company:           "5d3e27e3-40ae-46e8-a123-5b08b03d63b7",
  stage:             "1ad01c11-74f7-4c08-a139-5dab26c43e7e",
  business_model:    "12e27c12-3a78-4dab-81be-88f7001f36c5",
  funnel:            "725b9c69-2dc2-4e94-97d1-a3659412d529",
  contact_name:      "4ac9b2c5-d41c-4523-a39d-051dc5633042",
  contact_position:  "3fd5c475-b16b-4b8e-822e-bc8b78e87ca2",
  contact_email:     "e6b40d6e-f999-4ed3-a5b4-2d768b7e7133",
  contact_phone:     "8061325e-06db-416f-b63f-6131799181dd",
  channel:           "0830f7f7-c77c-499d-839f-46caca2a5d88",
  primary_contact:   "1f7ef9a3-7bc6-40d9-9dde-066c720d84c7",
  notes:             "5b35268f-d9a6-4d08-8d8c-c6f3e5e84215"
}.freeze

# ── Coba defaults for new leads ───────────────────────────────────────
DEFAULT_FUNNEL_ID     = "0c693a54-84af-4760-840d-372ccd33bd81" # Coba Pipeline
DEFAULT_STAGE         = "Inbound"
DEFAULT_BUSINESS_MODEL = "Banking"
DEFAULT_PEOPLE_STATUS = "Lead"

SOURCE_TO_CHANNEL = {
  "linkedin" => "LinkedIn",
  "direct"   => "Email",
  "referral" => "Referral",
  "seo"      => "Email",     # fallback; DenchClaw's enum doesn't have SEO
  "facebook" => "Email"      # ditto
}.freeze

# ── DuckDB helpers ────────────────────────────────────────────────────
# Uses CSV output mode — the `-json` mode has encoding quirks in the
# CLI versions installed at Coba today. CSV is unambiguous and easy to
# parse for the single-column lookups we do here.
def duckdb_query(sql)
  stdout, stderr, status = Open3.capture3("duckdb", DB_PATH, "-csv", "-header", "-c", sql)
  unless status.success?
    abort_with("duckdb query failed: #{stderr.strip}")
  end
  return [] if stdout.strip.empty?
  rows = CSV.parse(stdout, headers: true, skip_blanks: true)
  rows.map(&:to_h)
rescue CSV::MalformedCSVError => e
  abort_with("duckdb returned malformed CSV: #{e.message} — got: #{stdout[0, 300]}")
end

def duckdb_exec(sql)
  _stdout, stderr, status = Open3.capture3("duckdb", DB_PATH, "-c", sql)
  unless status.success?
    abort_with("duckdb exec failed: #{stderr.strip}")
  end
end

def sql_escape(value)
  return "NULL" if value.nil?
  "'" + value.to_s.gsub("'", "''") + "'"
end

def insert_entry_field(entry_id, field_id, value)
  return if value.nil? || value.to_s.empty?
  <<~SQL
    INSERT INTO entry_fields (id, entry_id, field_id, value, created_at, updated_at)
    VALUES (#{sql_escape(SecureRandom.uuid)}, #{sql_escape(entry_id)}, #{sql_escape(field_id)}, #{sql_escape(value)}, NOW(), NOW());
  SQL
end

def insert_entry(entry_id, object_id)
  <<~SQL
    INSERT INTO entries (id, object_id, sort_order, created_at, updated_at)
    VALUES (#{sql_escape(entry_id)}, #{sql_escape(object_id)}, 0, NOW(), NOW());
  SQL
end

def abort_with(msg)
  warn(msg)
  exit 1
end

# ── Lookup: existing person by email ──────────────────────────────────
def find_person_by_email(email)
  rows = duckdb_query(<<~SQL)
    SELECT e.id AS person_id
    FROM entries e
    JOIN entry_fields ef ON ef.entry_id = e.id
    WHERE e.object_id = #{sql_escape(OBJ_PEOPLE)}
      AND ef.field_id = #{sql_escape(FLD_PEOPLE[:email])}
      AND LOWER(ef.value) = LOWER(#{sql_escape(email)})
    LIMIT 1;
  SQL
  rows.first && rows.first["person_id"]
end

def find_deal_for_person(person_id)
  rows = duckdb_query(<<~SQL)
    SELECT e.id AS deal_id
    FROM entries e
    JOIN entry_fields ef ON ef.entry_id = e.id
    WHERE e.object_id = #{sql_escape(OBJ_DEAL)}
      AND ef.field_id = #{sql_escape(FLD_DEAL[:primary_contact])}
      AND ef.value = #{sql_escape(person_id)}
    LIMIT 1;
  SQL
  rows.first && rows.first["deal_id"]
end

def find_notes_for_deal(deal_id)
  rows = duckdb_query(<<~SQL)
    SELECT value
    FROM entry_fields
    WHERE entry_id = #{sql_escape(deal_id)}
      AND field_id = #{sql_escape(FLD_DEAL[:notes])}
    LIMIT 1;
  SQL
  rows.first && rows.first["value"]
end

# Compose an inbound-touch block to append to a deal's Notes. The tag
# "(touch:<external_id>)" in the header is the idempotency marker —
# before appending we grep existing Notes for this tag, skip if present.
# That way retries from the trigger layer don't multiply touches.
def format_touch(external_id:, source:, inquiry_type:, volume:, message:)
  timestamp = Time.now.utc.strftime("%Y-%m-%d %H:%M UTC")
  tag = external_id.to_s.strip.empty? ? "" : " (touch:#{external_id})"
  parts = []
  parts << "**#{timestamp} — inbound #{source} touch#{tag}**"
  parts << "- Inquiry type: #{inquiry_type}" unless inquiry_type.to_s.strip.empty?
  parts << "- Volume: #{volume}"              unless volume.to_s.strip.empty?
  if message.to_s.strip != ""
    parts << ""
    parts << message.to_s
  end
  parts.join("\n")
end

def upsert_deal_notes(deal_id, new_notes)
  existing = find_notes_for_deal(deal_id)
  if existing.nil?
    # no Notes row yet → insert fresh
    duckdb_exec(insert_entry_field(deal_id, FLD_DEAL[:notes], new_notes))
    :inserted
  else
    combined = "#{existing}\n\n---\n\n#{new_notes}"
    duckdb_exec(<<~SQL)
      UPDATE entry_fields
      SET value = #{sql_escape(combined)}, updated_at = NOW()
      WHERE entry_id = #{sql_escape(deal_id)}
        AND field_id = #{sql_escape(FLD_DEAL[:notes])};
    SQL
    :appended
  end
end

# ── Main ──────────────────────────────────────────────────────────────
input = JSON.parse(STDIN.read)

lead_email           = input.fetch("lead_email").to_s.strip
abort_with("lead_email is required") if lead_email.empty?

lead_name            = input["lead_name"].to_s.strip
lead_company         = (input["lead_company"].to_s.strip.empty? ? input["enriched_company"].to_s : input["lead_company"]).to_s.strip
lead_title           = input["lead_title"].to_s.strip
lead_phone           = input["lead_phone"].to_s.strip
lead_inquiry_type    = input["lead_inquiry_type"].to_s.strip
lead_volume          = input["lead_volume"].to_s.strip
lead_message         = input["lead_message"].to_s.strip
source               = input["source"].to_s.strip.downcase
platform_campaign_id = input["platform_campaign_id"].to_s.strip
external_id          = input["external_id"].to_s.strip
channel              = SOURCE_TO_CHANNEL[source] || "Email"

# Compose a Notes blob from the richer website-form fields. Persisted on
# the deal entry's Notes (richtext) column so the human doing qualify/
# review sees the full context without hunting. If none of the three are
# populated (e.g., LinkedIn path) this stays nil and we skip the insert.
notes_body = [
  (lead_inquiry_type.empty? ? nil : "**Inquiry type:** #{lead_inquiry_type}"),
  (lead_volume.empty?       ? nil : "**Monthly volume:** #{lead_volume}"),
  (lead_message.empty?      ? nil : "\n#{lead_message}")
].compact.join("\n")
notes_body = nil if notes_body.empty?

# Idempotency check — email is the dedup key across ALL sources (LinkedIn,
# website, direct, referral). Same email = one deal, regardless of channel.
# On dedup hit, UPSERT: we don't create a duplicate deal, but we DO append
# a timestamped touch block to the existing deal's Notes so re-engagement
# data (what they asked, volume, message) is preserved for the sales rep.
# Guarded by external_id tag — replays with the same trigger payload are
# no-ops.
existing_person_id = find_person_by_email(lead_email)
if existing_person_id
  existing_deal_id = find_deal_for_person(existing_person_id)
  if existing_deal_id
    warn "[create-crm-record] DEDUP_HIT email=#{lead_email} person_id=#{existing_person_id} deal_id=#{existing_deal_id} source=#{source}"

    # Only upsert if we actually have new touch data to add. LinkedIn-path
    # inputs don't include inquiry_type/volume/message, so for those we
    # silently return as before.
    has_touch_data = !(lead_inquiry_type.empty? && lead_volume.empty? && lead_message.empty?)
    appended = false
    if has_touch_data
      existing_notes = find_notes_for_deal(existing_deal_id).to_s
      touch_marker   = external_id.empty? ? nil : "(touch:#{external_id})"
      already_seen   = touch_marker && existing_notes.include?(touch_marker)

      if already_seen
        warn "[create-crm-record] TOUCH_REPLAY external_id=#{external_id} — existing Notes already has this tag, skipping append"
      else
        touch = format_touch(
          external_id:   external_id,
          source:        source.empty? ? "unknown" : source,
          inquiry_type:  lead_inquiry_type,
          volume:        lead_volume,
          message:       lead_message
        )
        result = upsert_deal_notes(existing_deal_id, touch)
        warn "[create-crm-record] TOUCH_#{result.to_s.upcase} deal_id=#{existing_deal_id} external_id=#{external_id} source=#{source}"
        appended = true
      end
    end

    puts JSON.dump({
      "person_id"     => existing_person_id,
      "deal_id"       => existing_deal_id,
      "was_duplicate" => true,
      "touch_appended" => appended
    })
    exit 0
  end
  # Person exists but no deal — continue to create a deal linked to them.
end

person_id = existing_person_id || SecureRandom.uuid
deal_id   = SecureRandom.uuid

deal_name =
  if !lead_company.empty? && !lead_name.empty?
    "#{lead_company} — #{lead_name}"
  elsif !lead_company.empty?
    lead_company
  elsif !lead_name.empty?
    lead_name
  else
    "New Lead (#{lead_email})"
  end

# Build SQL in a single transaction
statements = []
statements << "BEGIN TRANSACTION;"

unless existing_person_id
  statements << insert_entry(person_id, OBJ_PEOPLE)
  statements << insert_entry_field(person_id, FLD_PEOPLE[:full_name], lead_name.empty? ? lead_email : lead_name)
  statements << insert_entry_field(person_id, FLD_PEOPLE[:email],     lead_email)
  statements << insert_entry_field(person_id, FLD_PEOPLE[:phone],     lead_phone)
  statements << insert_entry_field(person_id, FLD_PEOPLE[:company],   lead_company)
  statements << insert_entry_field(person_id, FLD_PEOPLE[:job_title], lead_title)
  statements << insert_entry_field(person_id, FLD_PEOPLE[:status],    DEFAULT_PEOPLE_STATUS)
end

statements << insert_entry(deal_id, OBJ_DEAL)
statements << insert_entry_field(deal_id, FLD_DEAL[:name],             deal_name)
statements << insert_entry_field(deal_id, FLD_DEAL[:company],          lead_company)
statements << insert_entry_field(deal_id, FLD_DEAL[:stage],            DEFAULT_STAGE)
statements << insert_entry_field(deal_id, FLD_DEAL[:business_model],   DEFAULT_BUSINESS_MODEL)
statements << insert_entry_field(deal_id, FLD_DEAL[:funnel],           DEFAULT_FUNNEL_ID)
statements << insert_entry_field(deal_id, FLD_DEAL[:contact_name],     lead_name)
# Contact Position intentionally left blank. Cal.com direct bookings map
# lead_title from the meeting title (e.g. "Coba <> Customer"), which isn't
# a job title — filling it produced garbage. LinkedIn Lead Gen Forms will
# provide a real `job_title` field; wire it through when that lands.
statements << insert_entry_field(deal_id, FLD_DEAL[:contact_email],    lead_email)
statements << insert_entry_field(deal_id, FLD_DEAL[:contact_phone],    lead_phone)
statements << insert_entry_field(deal_id, FLD_DEAL[:channel],          channel)
statements << insert_entry_field(deal_id, FLD_DEAL[:primary_contact],  person_id)
statements << insert_entry_field(deal_id, FLD_DEAL[:notes],            notes_body)

statements << "COMMIT;"

sql = statements.compact.join("\n")
duckdb_exec(sql)

puts JSON.dump({
  "person_id"     => person_id,
  "deal_id"       => deal_id,
  "was_duplicate" => false
})
