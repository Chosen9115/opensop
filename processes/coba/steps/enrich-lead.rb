#!/usr/bin/env ruby
# frozen_string_literal: true

# PRIVATE — Coba fork only.
#
# Stub enrichment. Reads lead_email + lead_company from stdin, writes
# enriched fields to stdout. Today: derives company from email domain if
# none provided, returns placeholder size bucket. When we have a real
# enrichment provider (Clearbit, Apollo, People Data Labs), swap this
# body for an HTTP call and parse the response.

require "json"

input = JSON.parse(STDIN.read)

email = input["lead_email"].to_s
company_from_input = input["lead_company"].to_s.strip

derived_company =
  if !company_from_input.empty?
    company_from_input
  elsif email.include?("@")
    domain = email.split("@").last
    # Cheap heuristic: strip tld, title-case the rest.
    root = domain.split(".").first.to_s
    root.empty? ? "Unknown" : root.capitalize
  else
    "Unknown"
  end

# Real provider wiring replaces these with actual lookups.
puts JSON.dump({
  "enriched_company"    => derived_company,
  "company_size_bucket" => "unknown",
  "industry"            => "unknown"
})
