#!/usr/bin/env ruby
# frozen_string_literal: true

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
  channel:           "0830f7f7-c77c-499d-839f-46caca2a5d88",
  primary_contact:   "1f7ef9a3-7bc6-40d9-9dde-066c720d84c7"
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

# ── Main ──────────────────────────────────────────────────────────────
input = JSON.parse(STDIN.read)

lead_email           = input.fetch("lead_email").to_s.strip
abort_with("lead_email is required") if lead_email.empty?

lead_name            = input["lead_name"].to_s.strip
lead_company         = (input["lead_company"].to_s.strip.empty? ? input["enriched_company"].to_s : input["lead_company"]).to_s.strip
lead_title           = input["lead_title"].to_s.strip
source               = input["source"].to_s.strip.downcase
platform_campaign_id = input["platform_campaign_id"].to_s.strip
channel              = SOURCE_TO_CHANNEL[source] || "Email"

# Idempotency check
existing_person_id = find_person_by_email(lead_email)
if existing_person_id
  existing_deal_id = find_deal_for_person(existing_person_id)
  if existing_deal_id
    puts JSON.dump({
      "person_id"     => existing_person_id,
      "deal_id"       => existing_deal_id,
      "was_duplicate" => true
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
statements << insert_entry_field(deal_id, FLD_DEAL[:contact_position], lead_title)
statements << insert_entry_field(deal_id, FLD_DEAL[:contact_email],    lead_email)
statements << insert_entry_field(deal_id, FLD_DEAL[:channel],          channel)
statements << insert_entry_field(deal_id, FLD_DEAL[:primary_contact],  person_id)

statements << "COMMIT;"

sql = statements.compact.join("\n")
duckdb_exec(sql)

puts JSON.dump({
  "person_id"     => person_id,
  "deal_id"       => deal_id,
  "was_duplicate" => false
})
