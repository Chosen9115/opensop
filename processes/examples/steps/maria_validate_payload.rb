#!/usr/bin/env ruby
# frozen_string_literal: true

# Automated step: validate-payload (maria-linkedin-post-approval)
#
# Reads an inputs JSON from stdin:
#   {
#     "campaign_slug": string,
#     "post_id": string,
#     "post_title": string,
#     "post_body": string,
#     "target_account": "cobaremote-company" | "carlos-personal",
#     "proposed_publish_at": ISO8601 string,
#     "approval_channel": "slack-maria" | "slack-coba-ops" | "manual",
#     "already_published_url": string | nil
#   }
#
# Emits an outputs JSON to stdout:
#   { "valid": boolean, "validation_notes": string, "is_retrofit": boolean }
#
# On invalid input: valid=false, non-zero notes, exit 0.
# The engine routes via condition on `valid`; we never exit non-zero here.

require "json"
require "time"

raw = $stdin.read
payload =
  begin
    raw.to_s.strip.empty? ? {} : JSON.parse(raw)
  rescue JSON::ParserError
    {}
  end

errors = []

# ── Required non-empty string fields ────────────────────────────────────────
%w[campaign_slug post_id post_title post_body proposed_publish_at].each do |field|
  val = payload[field]
  errors << "#{field} is required and must be a non-empty string" if val.nil? || val.to_s.strip.empty?
end

# ── Enum: target_account ────────────────────────────────────────────────────
valid_accounts = %w[cobaremote-company carlos-personal]
account = payload["target_account"].to_s
unless valid_accounts.include?(account)
  errors << "target_account must be one of: #{valid_accounts.join(', ')} (got: #{account.inspect})"
end

# ── Enum: approval_channel ──────────────────────────────────────────────────
valid_channels = %w[slack-maria slack-coba-ops manual]
channel = payload["approval_channel"].to_s
unless valid_channels.include?(channel)
  errors << "approval_channel must be one of: #{valid_channels.join(', ')} (got: #{channel.inspect})"
end

# ── proposed_publish_at: must parse as ISO8601 ───────────────────────────────
publish_at_raw = payload["proposed_publish_at"].to_s
unless publish_at_raw.strip.empty?
  begin
    Time.iso8601(publish_at_raw)
  rescue ArgumentError
    begin
      Time.parse(publish_at_raw)
    rescue ArgumentError
      errors << "proposed_publish_at could not be parsed as a datetime (got: #{publish_at_raw.inspect})"
    end
  end
end

# ── post_body length: 50..3000 chars (LinkedIn org-post sweet-spot) ──────────
body = payload["post_body"].to_s
unless body.strip.empty?
  len = body.length
  if len < 50
    errors << "post_body is too short (#{len} chars); minimum is 50"
  elsif len > 3000
    errors << "post_body is too long (#{len} chars); maximum is 3000"
  end
end

# ── already_published_url: must start with the expected LinkedIn prefix ───────
retrofit_url = payload["already_published_url"].to_s.strip
is_retrofit = !retrofit_url.empty?
if is_retrofit && !retrofit_url.start_with?("https://www.linkedin.com/posts/")
  errors << "already_published_url must begin with https://www.linkedin.com/posts/ (got: #{retrofit_url.inspect})"
end

# ── Emit result ──────────────────────────────────────────────────────────────
valid = errors.empty?
notes = valid ? "ok" : errors.join("; ")

puts JSON.generate("valid" => valid, "validation_notes" => notes, "is_retrofit" => is_retrofit)
