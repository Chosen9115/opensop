#!/usr/bin/env ruby
# STUB — real implementation enforces two ceilings:
#   1. Global cap: at most 40 incidents per run across all projects.
#      Sort by occurrences_count DESC, then last_seen DESC before slicing.
#   2. Per-project rate limit: at most 5 runs per project per day.
#      Scan today's receipts to count how many runs already landed.
#
# Incidents beyond the cap get a `deferred_over_cap` receipt (written by the
# Rust backend, not this script). This script just signals how many were cut.
#
# Port from: appsignal_responder.rs :: apply_budget_caps

require "json"
require "time"

MAX_INCIDENTS = 40
MAX_RUNS_PER_PROJECT_PER_DAY = 5

inputs   = JSON.parse($stdin.read)
all      = Array(inputs["incidents"])
projects = Array(inputs["projects"])
run_id   = inputs["run_id"]

# Sort by occurrences_count desc, last_seen desc.
sorted = all.sort_by { |i| [-i["occurrences_count"].to_i, -Time.parse(i["last_seen"]).to_i] }

# Stub: skip the per-project rate-limit check against live receipts.
# Real implementation reads today's receipts.jsonl and counts distinct run_ids per project.
run_blocked = false

to_process = sorted.first(MAX_INCIDENTS)
deferred   = sorted.size - to_process.size

$stdout.puts JSON.dump({
  "incidents_to_process" => to_process,
  "deferred_count"       => deferred,
  "run_blocked"          => run_blocked
})
