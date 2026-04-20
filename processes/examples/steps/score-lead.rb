#!/usr/bin/env ruby
# frozen_string_literal: true

# Automated step: score-lead
#
# Reads an inputs JSON from stdin:
#   { "budget": number, "timeline": "immediate"|"3m"|"6m"|"unknown", "notes": string }
#
# Emits an outputs JSON:
#   { "score": number (0..100), "qualified": boolean }

require "json"

raw = $stdin.read
payload =
  begin
    raw.to_s.strip.empty? ? {} : JSON.parse(raw)
  rescue JSON::ParserError
    {}
  end

budget = payload["budget"].to_f
timeline = payload["timeline"].to_s

timeline_bump =
  case timeline
  when "immediate" then 40
  when "3m" then 20
  else 10
  end

score = (budget / 1000.0 + timeline_bump).clamp(0, 100)
qualified = budget >= 5000 && timeline != "unknown"

puts JSON.generate("score" => score.round(2), "qualified" => qualified)
