#!/usr/bin/env ruby
# STUB — re-fetches a specific incident from AppSignal to check current state.
# Real implementation calls the same GraphQL endpoint as fetch-incidents.rb
# but queries by incident ID.
#
# Port from: appsignal_client.rs :: fetch_incident_by_id
#
# This stub returns a "closed" incident with last_seen before merged_at,
# which produces a fix_verified verdict in evaluate-regression.rb.
# Swap current_state to "open" and last_seen to after merged_at to test
# regression_detected.

require "json"
require "time"

inputs      = JSON.parse($stdin.read)
incident_id = inputs["incident_id"]
merged_at   = Time.parse(inputs["merged_at"])

# Stub: pretend the incident closed 2 days after merge.
current_last_seen = (merged_at - 3600).iso8601  # 1h before merge = fix held
days_since_merge  = ((Time.now - merged_at) / 86_400).round(1)

$stdout.puts JSON.dump({
  "current_last_seen"         => current_last_seen,
  "current_state"             => "closed",
  "current_occurrences_count" => 0,
  "days_since_merge"          => days_since_merge
})
