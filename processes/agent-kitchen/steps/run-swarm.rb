#!/usr/bin/env ruby
# STUB — real implementation invokes claude-swarm inside the worktree.
#
# Real flow (matches dispatcher SKILL.md MODE: fix-appsignal):
#   1. Build a task string from incident context.
#   2. cd into worktree_path.
#   3. Run: claude-swarm start --vibe --task "<task>"
#   4. Check exit code and whether a commit was made (git log HEAD..origin/main --oneline).
#
# This stub returns committed: false so safety-gate and push are skipped,
# making it safe to run without actually touching any repo.
# Flip committed: true (and create a real commit first) to exercise the full path.

require "json"

inputs       = JSON.parse($stdin.read)
worktree     = inputs["worktree_path"]
incident     = inputs["incident"]
file         = inputs["file"]
line         = inputs["line"]

exception_name = incident["exception_name"]
message        = incident["message"]
action         = incident["action_name"]

task = [
  "Fix AppSignal incident in #{action}:",
  "Exception: #{exception_name} — #{message}",
  file ? "Start at #{file}:#{line}" : "Trace from #{action}"
].join("\n")

$stderr.puts "[run-swarm stub] would run: claude-swarm start --vibe"
$stderr.puts "[run-swarm stub] task: #{task.lines.first.chomp}"
$stderr.puts "[run-swarm stub] worktree: #{worktree}"
$stderr.puts "[run-swarm stub] returning committed: false (stub safety)"

$stdout.puts JSON.dump({
  "swarm_exit_code" => 0,
  "diff_summary"    => "",
  "committed"       => false
})
