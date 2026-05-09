#!/usr/bin/env ruby
# frozen_string_literal: true

# Automated step: categorize-ticket
#
# Reads an inputs JSON from stdin:
#   { "subject": string, "body": string, "channel": string }
#
# Emits an outputs JSON to stdout:
#   { "category": "billing"|"technical"|"account"|"feature_request"|"other",
#     "urgency": "critical"|"high"|"normal"|"low",
#     "word_count": number }

require "json"

raw = $stdin.read
payload =
  begin
    raw.to_s.strip.empty? ? {} : JSON.parse(raw)
  rescue JSON::ParserError
    {}
  end

subject = payload["subject"].to_s.downcase
body    = payload["body"].to_s.downcase
text    = "#{subject} #{body}"

# Deterministic keyword-based categorization
category =
  if text.match?(/invoice|payment|charge|refund|billing|subscription|price/)
    "billing"
  elsif text.match?(/error|crash|bug|broken|fail|exception|timeout|outage|down/)
    "technical"
  elsif text.match?(/password|login|account|access|permission|locked|2fa|mfa/)
    "account"
  elsif text.match?(/feature|request|suggest|wish|would be great|can you add/)
    "feature_request"
  else
    "other"
  end

# Urgency from keywords and channel
urgency =
  if text.match?(/urgent|asap|critical|production down|outage|emergency/)
    "critical"
  elsif text.match?(/broken|fail|error|cannot|can't|not working/)
    "high"
  elsif payload["channel"].to_s == "phone"
    "high"
  else
    "normal"
  end

word_count = payload["body"].to_s.split.length

puts JSON.generate(
  "category"   => category,
  "urgency"    => urgency,
  "word_count" => word_count
)
