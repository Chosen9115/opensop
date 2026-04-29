#!/usr/bin/env ruby
# Creates an isolated git worktree off main.
# Branch name: fix/appsignal-<first-8-chars-of-incident-id>
#
# The worktree is created inside the project's .git/worktrees/ so it stays
# off the main working tree. Cleaned up by push-and-create-pr.rb after push,
# or by safety-gate.rb if the gate fails.

require "json"

inputs       = JSON.parse($stdin.read)
incident_id  = inputs["incident_id"]
project_path = inputs["project_path"]

short_id    = incident_id.gsub("-", "")[0, 8]
branch_name = "fix/appsignal-#{short_id}"
worktree_dir = File.join(project_path, "..", ".worktrees", branch_name)

unless Dir.exist?(project_path)
  $stderr.puts "project_path not found: #{project_path}"
  exit 1
end

# Ensure the branch doesn't already exist remotely.
`git -C #{project_path} fetch origin main 2>/dev/null`

# Create the worktree on a new branch off main.
out = `git -C #{project_path} worktree add -b #{branch_name} #{worktree_dir} origin/main 2>&1`
unless $?.success?
  $stderr.puts "git worktree add failed: #{out}"
  exit 1
end

$stdout.puts JSON.dump({
  "worktree_path" => worktree_dir,
  "branch_name"   => branch_name
})
