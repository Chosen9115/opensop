#!/usr/bin/env ruby
# frozen_string_literal: true

# Smoke step: v02_echo_score
#
# Test fixture. Backs spec/fixtures/processes/v02-smoke-exit-when.sop.yaml — it
# lives under processes/steps/ (not in spec/fixtures) because Automated `run:`
# paths resolve relative to processes/ (see automated.rb#resolve_script_path).
# Not a shipped process; intentionally kept out of the seeded set.
#
# Reads { "score": <number> } from stdin and echoes a fixed-shape result so
# multiple steps in the exit_when smoke process can re-use the same script.

require "json"

raw = $stdin.read
input =
  begin
    raw.to_s.strip.empty? ? {} : JSON.parse(raw)
  rescue JSON::ParserError
    {}
  end

puts JSON.dump(
  "score"         => input["score"],
  "outcome"       => "passed",
  "stage_reached" => "finalize"
)
