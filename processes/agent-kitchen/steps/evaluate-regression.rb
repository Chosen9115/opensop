#!/usr/bin/env ruby
# Determines the regression verdict by comparing current_last_seen against
# merged_at with a 24h tolerance window.
#
# Rules (mirror appsignal_regression.rs):
#   fix_verified        — last_seen < merged_at (error stopped before deploy)
#   regression_detected — last_seen > merged_at + 24h (error recurred after deploy)
#   deferred_grace      — last_seen within [merged_at, merged_at + 24h]
#                         or days_since_merge < 3 (still in grace window)

require "json"
require "time"

TOLERANCE_SECONDS = 86_400  # 24 hours
GRACE_DAYS        = 3

inputs           = JSON.parse($stdin.read)
merged_at        = Time.parse(inputs["merged_at"])
current_last_seen = Time.parse(inputs["current_last_seen"])
days_since_merge  = inputs["days_since_merge"].to_f

verdict, reason =
  if days_since_merge < GRACE_DAYS && current_last_seen > merged_at
    ["deferred_grace", "within #{GRACE_DAYS}-day grace window"]
  elsif current_last_seen <= merged_at
    ["fix_verified", "last_seen (#{inputs["current_last_seen"]}) is before merged_at"]
  elsif current_last_seen > merged_at + TOLERANCE_SECONDS
    ["regression_detected", "last_seen #{days_since_merge.round(1)}d after merge, exceeds 24h tolerance"]
  else
    ["deferred_grace", "last_seen within 24h tolerance window"]
  end

$stdout.puts JSON.dump({
  "verdict"        => verdict,
  "verdict_reason" => reason
})
