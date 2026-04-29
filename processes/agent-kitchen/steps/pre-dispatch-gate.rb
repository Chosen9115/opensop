#!/usr/bin/env ruby
# Checks two ceilings before spawning a worktree:
#   1. Phase must be >= 2.  Phase 1 is classifier-only — no dispatch.
#   2. At most 1 open fix-PR per project at a time.
#      Uses `gh pr list` to count open branches matching fix/appsignal-*.
#
# This is the single place where phase advancement is enforced.

require "json"

inputs  = JSON.parse($stdin.read)
project = inputs["project"]
repo    = inputs["repo"]
phase   = inputs["phase"].to_i

if phase < 2
  $stdout.puts JSON.dump({ "gate_passed" => false, "gate_reason" => "phase_1_only" })
  exit 0
end

# Check open fix-PR ceiling using gh.
open_fix_prs = begin
  result = `gh pr list --repo #{repo} --state open --json headRefName --limit 50 2>/dev/null`
  prs = JSON.parse(result)
  prs.count { |pr| pr["headRefName"].to_s.start_with?("fix/appsignal-") }
rescue StandardError
  0
end

if open_fix_prs >= 1
  $stdout.puts JSON.dump({ "gate_passed" => false, "gate_reason" => "open_pr_ceiling_hit" })
  exit 0
end

$stdout.puts JSON.dump({ "gate_passed" => true, "gate_reason" => "" })
