#!/usr/bin/env ruby
# frozen_string_literal: true

# Smoke step: v02_passthrough_messages
#
# Test fixture. Backs spec/fixtures/processes/v02-smoke-loop-llm.sop.yaml — it
# lives under processes/steps/ (not in spec/fixtures) because Automated `run:`
# paths resolve relative to processes/ (see automated.rb#resolve_script_path).
# Not a shipped process; intentionally kept out of the seeded set.
#
# Reads { "messages": [...] } from stdin and echoes the same array back so the
# downstream loop step has a collection-shaped output to fan over.

require "json"

raw = $stdin.read
input =
  begin
    raw.to_s.strip.empty? ? {} : JSON.parse(raw)
  rescue JSON::ParserError
    {}
  end

puts JSON.dump("messages" => input["messages"])
