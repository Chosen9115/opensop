#!/usr/bin/env ruby
# frozen_string_literal: true

# Automated step: create-account
#
# Reads an inputs JSON from stdin:
#   { "business_record": { ... }, "entity_id": "..." }
#
# Emits an outputs JSON matching the step's output schema:
#   { "account_id": "acct_<hex8>", "member_id": "mem_<hex8>" }

require "json"
require "securerandom"

raw = $stdin.read
begin
  raw.to_s.strip.empty? ? {} : JSON.parse(raw)
rescue JSON::ParserError
  {}
end

outputs = {
  "account_id" => "acct_#{SecureRandom.hex(4)}",
  "member_id"  => "mem_#{SecureRandom.hex(4)}"
}

puts JSON.generate(outputs)
