#!/usr/bin/env ruby
# frozen_string_literal: true

# Automated step: capture-published-url (maria-linkedin-post-approval)
#
# Reads an inputs JSON from stdin:
#   { "manual_url": string | nil, "retrofit_url": string | nil }
#
# Prefers retrofit_url if non-empty (retro-fit path), else manual_url.
#
# Emits an outputs JSON to stdout:
#   { "published_url": string, "source": "manual-publish" | "retrofit" }
#
# If both are empty, published_url is "" and source is "manual-publish".
# The engine's required_if on the publish-gate step enforces URL presence
# upstream on the approve path, so reaching here with both empty should not
# happen in production.
# TODO: alert / hard-fail if both URLs are empty once engine supports it.

require "json"

raw = $stdin.read
payload =
  begin
    raw.to_s.strip.empty? ? {} : JSON.parse(raw)
  rescue JSON::ParserError
    {}
  end

retrofit_url = payload["retrofit_url"].to_s.strip
manual_url   = payload["manual_url"].to_s.strip

if !retrofit_url.empty?
  puts JSON.generate("published_url" => retrofit_url, "source" => "retrofit")
elsif !manual_url.empty?
  puts JSON.generate("published_url" => manual_url, "source" => "manual-publish")
else
  # Both empty — should not occur in production (publish-gate required_if guards this).
  puts JSON.generate("published_url" => "", "source" => "manual-publish")
end
