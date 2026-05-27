#!/usr/bin/env ruby
# frozen_string_literal: true

# Automated step: log-to-gbrain (maria-linkedin-post-approval)
#
# Reads an inputs JSON from stdin:
#   {
#     "published_url": string,
#     "post_id": string,
#     "campaign_slug": string,
#     "target_account": string,
#     "decision": string
#   }
#
# Behaviour:
#   - If ENV["MARKETING_GBRAIN_LOG_URL"] is set, POST the payload there (HTTP).
#   - Otherwise, append a single-line JSON record to log/maria_linkedin_log.jsonl
#     (relative to the Rails root, resolved via __dir__).
#
# Emits an outputs JSON to stdout:
#   { "logged": boolean, "gbrain_entry_id": string }
#
# GAP: The real marketing-gbrain HTTP contract (auth, endpoint schema, retry
# policy) is TBD. This stub is safe to run in dev/CI without any secrets.
# When the contract is known, replace the ENV branch body and remove this comment.

require "json"
require "digest"
require "time"

raw = $stdin.read
payload =
  begin
    raw.to_s.strip.empty? ? {} : JSON.parse(raw)
  rescue JSON::ParserError
    {}
  end

log_entry = payload.merge("logged_at" => Time.now.utc.iso8601)

gbrain_url = ENV["MARKETING_GBRAIN_LOG_URL"].to_s.strip

if !gbrain_url.empty?
  require "net/http"
  require "uri"

  uri = URI.parse(gbrain_url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == "https"
  http.open_timeout = 5
  http.read_timeout = 10

  req = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json")
  req.body = JSON.generate(log_entry)
  resp = http.request(req)

  logged = resp.code.to_i < 300
  entry_id = "gbrain-#{Digest::SHA1.hexdigest(log_entry.to_json)[0, 12]}"
  puts JSON.generate("logged" => logged, "gbrain_entry_id" => entry_id)
else
  # Local fallback: append to log/maria_linkedin_log.jsonl at the repo root.
  # __dir__ is processes/examples/steps; three "..": → repo root.
  log_dir = File.expand_path("../../..", __dir__) + "/log"
  Dir.mkdir(log_dir) unless Dir.exist?(log_dir)
  log_path = File.join(log_dir, "maria_linkedin_log.jsonl")

  File.open(log_path, "a") { |f| f.puts(JSON.generate(log_entry)) }

  entry_id = "local-#{Digest::SHA1.hexdigest(log_entry.to_json)[0, 12]}"
  puts JSON.generate("logged" => true, "gbrain_entry_id" => entry_id)
end
