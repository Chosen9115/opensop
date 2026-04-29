#!/usr/bin/env ruby
# STUB — real implementation does two things:
#   1. Scans logs/appsignal-responder/receipts.jsonl for the last 60 days,
#      collecting entries with outcome in {dispatched, pr-created, merged, resolved}.
#   2. Runs `gh pr list --state all --limit 100 --json ...` per project and
#      finds PRs whose title/body contains "AppSignal #<number>" or whose
#      branch matches fix/appsignal-<first-8-of-id>.
#
# Port from: appsignal_responder.rs :: build_known_work

require "json"
require "time"

inputs   = JSON.parse($stdin.read)
projects = Array(inputs["projects"])

receipts_path = File.join(Dir.home, "workspace/workspace/agent-kitchen/logs/appsignal-responder/receipts.jsonl")

receipt_entries = []
if File.exist?(receipts_path)
  cutoff = Time.now - 60 * 86_400
  File.foreach(receipts_path) do |line|
    entry = JSON.parse(line.strip) rescue next
    ts = Time.parse(entry["ts"]) rescue nil
    next unless ts && ts > cutoff
    next unless %w[dispatched pr-created merged resolved].include?(entry["outcome"])
    next unless entry.dig("notes") && JSON.parse(entry["notes"])["incident_id"]

    notes = JSON.parse(entry["notes"])
    receipt_entries << {
      "source"          => "receipt",
      "incident_id"     => notes["incident_id"],
      "incident_number" => notes["incident_number"],
      "outcome"         => entry["outcome"],
      "pr_url"          => notes["pr_url"],
      "ts"              => entry["ts"]
    }
  rescue StandardError
    next
  end
end

# Stub: skip real `gh pr list` call — no open PRs assumed for smoke test.
# Real implementation: for each project run:
#   gh pr list --state all --limit 100 \
#     --json number,title,body,headRefName,state \
#     --repo coba-ai/<project>
# Then match on "AppSignal #<number>" or "fix/appsignal-<id[:8]>" branch.

known_work = receipt_entries.uniq { |e| e["incident_id"] }.first(100)

$stdout.puts JSON.dump({
  "known_work"       => known_work,
  "known_work_count" => known_work.size
})
