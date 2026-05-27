#!/usr/bin/env ruby
# frozen_string_literal: true

# Automated step: mark-complete (maria-linkedin-post-approval)
#
# Reads an inputs JSON from stdin:
#   {
#     "decision": "approve" | "reject",
#     "published_url": string | nil,
#     "metrics_24h": object | nil,
#     "metrics_7d": object | nil
#   }
#
# Emits an outputs JSON to stdout:
#   { "final_status": "complete" | "rejected_no_publish" }
#
# Runs on ALL paths (no step condition) to ensure the process always emits a
# terminal state, regardless of the approve/reject branch.

require "json"

raw = $stdin.read
payload =
  begin
    raw.to_s.strip.empty? ? {} : JSON.parse(raw)
  rescue JSON::ParserError
    {}
  end

decision = payload["decision"].to_s.strip

final_status =
  if decision == "reject"
    "rejected_no_publish"
  else
    "complete"
  end

puts JSON.generate("final_status" => final_status)
