#!/usr/bin/env ruby
# frozen_string_literal: true

# Automated step: stamp-release
#
# Reads an inputs JSON from stdin:
#   { "service": string, "release_notes": string, "base_version": string }
#
# Emits an outputs JSON to stdout:
#   { "version": string, "build_id": string, "artifact_tag": string }
#
# NOTE: Does not make any external calls. Version stamping is deterministic:
# it increments the patch segment of base_version and generates a stable
# build_id from the release_notes digest. Suitable for demo and CI dry-runs.

require "json"
require "digest"

raw = $stdin.read
payload =
  begin
    raw.to_s.strip.empty? ? {} : JSON.parse(raw)
  rescue JSON::ParserError
    {}
  end

service       = payload["service"].to_s.strip.gsub(/[^a-z0-9-]/i, "-").downcase
release_notes = payload["release_notes"].to_s
base          = payload["base_version"].to_s.strip

# Parse semver; fall back to 0.0.0 on any format problem
parts = base.match(/\A(\d+)\.(\d+)\.(\d+)\z/)
major, minor, patch =
  if parts
    [ parts[1].to_i, parts[2].to_i, parts[3].to_i + 1 ]
  else
    [ 0, 1, 0 ]
  end

version    = "#{major}.#{minor}.#{patch}"
# Short, stable identifier derived from content — not time-based
digest     = Digest::SHA256.hexdigest("#{service}:#{version}:#{release_notes}")[0, 8]
build_id   = "build-#{digest}"
artifact_tag = "#{service}:#{version}-#{digest}"

puts JSON.generate(
  "version"      => version,
  "build_id"     => build_id,
  "artifact_tag" => artifact_tag
)
