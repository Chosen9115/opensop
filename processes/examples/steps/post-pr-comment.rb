#!/usr/bin/env ruby
# frozen_string_literal: true

# Automated step: post-pr-comment
#
# Demo stub — does NOT call GitHub. In a real deployment this script would
# use the GitHub API (or gh CLI) to post a review comment. For v0.1 it
# prints the comment body to stdout and emits a simulated success result.
#
# Reads an inputs JSON from stdin:
#   { "pr_url": string, "review_decision": "approve"|"request_changes"|"comment",
#     "summary": string, "line_comments": array }
#
# Emits an outputs JSON to stdout:
#   { "comment_posted": boolean, "comment_url": string }

require "json"

raw = $stdin.read
payload =
  begin
    raw.to_s.strip.empty? ? {} : JSON.parse(raw)
  rescue JSON::ParserError
    {}
  end

pr_url          = payload["pr_url"].to_s
decision        = payload["review_decision"].to_s
summary         = payload["summary"].to_s
line_comments   = Array(payload["line_comments"])

# Simulate a comment URL derived from the PR URL so output is deterministic
pr_number = pr_url.match(/\/pull\/(\d+)/)&.captures&.first || "0"
comment_url = "#{pr_url.chomp("/")}#pullrequestreview-demo-#{pr_number}"

$stderr.puts "[post-pr-comment] DEMO MODE — no real GitHub call made"
$stderr.puts "[post-pr-comment] Would post #{decision.upcase} to #{pr_url}"
$stderr.puts "[post-pr-comment] Summary: #{summary[0, 120]}..."
$stderr.puts "[post-pr-comment] Line comments: #{line_comments.length}"

puts JSON.generate(
  "comment_posted" => true,
  "comment_url"    => comment_url
)
