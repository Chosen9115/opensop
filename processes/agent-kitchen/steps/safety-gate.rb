#!/usr/bin/env ruby
# Inspects the swarm's local commit against size and scope limits.
# If gate fails, removes the worktree so nothing is left dangling.
#
# Limits (mirror appsignal_gates::* in Rust):
#   MAX_FILES      = 3
#   MAX_ADDITIONS  = 200
#   critical_paths: loaded from the project config in agent-kitchen
#
# Port from: src-tauri/src/conflict_gates.rs (same shape)

require "json"

MAX_FILES     = 3
MAX_ADDITIONS = 200

# Critical paths per project — mirror projects/*.md in agent-kitchen.
CRITICAL_PATHS = {
  "coba" => %w[
    app/services/monex app/services/fx app/services/payments
    app/services/batch app/services/onboarding app/controllers/members/onboarding
    app/services/privy app/services/wallet app/models/transaction.rb app/models/payment.rb
  ],
  "pouch" => %w[
    app/controllers/api/v1/orders_controller.rb app/controllers/api/v1/quotes_controller.rb
    app/models/quote.rb app/services/mxn_to_usdc_transfer.rb
    app/services/usd_to_mxn_transfer.rb app/services/jwt_key_provider.rb
  ],
  "ddqpro" => %w[
    app/models/organization.rb app/models/investment_product.rb app/models/ddq.rb
    app/services/suggestion_service.rb app/services/embedding_service.rb
    app/services/llm_service app/services/ai_service/auto_answer
    app/jobs/document_processing_job.rb app/jobs/ddq_import_job.rb
  ]
}.freeze

inputs   = JSON.parse($stdin.read)
worktree = inputs["worktree_path"]
project  = inputs["project"]

unless Dir.exist?(worktree.to_s)
  $stdout.puts JSON.dump({
    "files_changed" => 0, "additions" => 0,
    "critical_path_hit" => false,
    "gate_passed" => false, "gate_reason" => "worktree_not_found"
  })
  exit 0
end

# Count changed files and additions in the tip commit.
stat_out = `git -C #{worktree} diff --stat HEAD~1 HEAD 2>/dev/null`.strip
files_changed = `git -C #{worktree} diff --name-only HEAD~1 HEAD 2>/dev/null`.strip.lines.count
additions     = `git -C #{worktree} diff --numstat HEAD~1 HEAD 2>/dev/null`
                .lines.sum { |l| l.split("\t").first.to_i }

changed_files = `git -C #{worktree} diff --name-only HEAD~1 HEAD 2>/dev/null`.strip.lines.map(&:chomp)

critical_globs = CRITICAL_PATHS[project] || []
critical_hit   = changed_files.any? { |f| critical_globs.any? { |g| f.start_with?(g) } }

reason =
  if critical_hit        then "critical_path"
  elsif files_changed > MAX_FILES   then "too_many_files"
  elsif additions > MAX_ADDITIONS   then "too_many_additions"
  end

gate_passed = reason.nil?

# Clean up worktree if gate failed.
unless gate_passed
  `git -C #{worktree}/.. worktree remove --force #{worktree} 2>/dev/null`
end

$stdout.puts JSON.dump({
  "files_changed"     => files_changed,
  "additions"         => additions,
  "critical_path_hit" => critical_hit,
  "gate_passed"       => gate_passed,
  "gate_reason"       => reason || ""
})
