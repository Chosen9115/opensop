# frozen_string_literal: true

# ──────────────────────────────────────────────────────────────────────
# DenchClaw Bridge
#
# A tiny Sinatra service that runs on the DenchClaw host (a dedicated
# Coba laptop) and gives Fly-hosted OpenSOP a network endpoint to
# insert leads into the local DuckDB.
#
# Exposed endpoints:
#   GET  /healthz          → 200 ok (no auth; used by funnel health)
#   POST /leads            → inserts into DenchClaw; bearer-token-auth'd
#   POST /circleback/match → finds a Circleback meeting matching
#                            { attendee_email, meeting_time }; auth'd
#
# Everything else → 404. No directory listing, no static files, no
# introspection.
#
# The insertion logic is delegated to the existing `create-crm-record.rb`
# script (the same one the local `lead-capture` process uses). The bridge
# is a thin shell-out wrapper so there's one source of truth for the
# DuckDB write semantics.
#
# Runs as launchd agent on macOS; see coba.denchclaw-bridge.plist.
# ──────────────────────────────────────────────────────────────────────

require "sinatra/base"
require "rack/protection/host_authorization"
require "json"
require "open3"
require "timeout"

# Sinatra 4.x + rack-protection 4.x wire HostAuthorization independently of
# `set :protection`, and none of the documented per-middleware options (tried
# set :protection, except / host_authorization: {allow_if: ...} / disable
# :protection) actually bypass it. This bridge is reached via Tailscale
# Funnel (hostname like *.ts.net), which the default allowlist rejects, so
# every inbound request was 403ing with "Host not permitted". Bearer token
# on POST /leads is the real auth. Monkeypatch HostAuthorization to a
# pass-through — ugly but definitive, and scoped to this process only.
module Rack
  module Protection
    class HostAuthorization
      def call(env)
        @app.call(env)
      end
    end
  end
end

module DenchClawBridge
  class App < Sinatra::Base
    # ── Config ──────────────────────────────────────────────────────
    TOKEN          = ENV["DENCHCLAW_BRIDGE_TOKEN"].to_s.freeze
    CRM_SCRIPT     = ENV["DENCHCLAW_BRIDGE_SCRIPT"].to_s.freeze
    TIMEOUT_SECS   = (ENV["DENCHCLAW_BRIDGE_TIMEOUT"] || "30").to_i
    CIRCLEBACK_CLI = (ENV["CIRCLEBACK_CLI"] || "/Users/c/.npm-global/bin/circleback").freeze

    configure do
      set :show_exceptions, false
      set :raise_errors, false
      set :logging, true


      if TOKEN.empty?
        warn "[denchclaw-bridge] FATAL: DENCHCLAW_BRIDGE_TOKEN is not set"
        exit 1
      end

      unless File.exist?(CRM_SCRIPT) && File.executable?(CRM_SCRIPT)
        warn "[denchclaw-bridge] FATAL: DENCHCLAW_BRIDGE_SCRIPT is not executable at #{CRM_SCRIPT.inspect}"
        exit 1
      end
    end

    # ── Auth helper ─────────────────────────────────────────────────
    helpers do
      def authenticated!
        header = request.env["HTTP_AUTHORIZATION"].to_s
        unless header.start_with?("Bearer ")
          halt 401, { "Content-Type" => "application/json" },
               JSON.dump(error: "missing_bearer_token")
        end
        presented = header.sub(/\ABearer\s+/, "").strip
        unless secure_compare(presented, TOKEN)
          halt 401, { "Content-Type" => "application/json" },
               JSON.dump(error: "invalid_token")
        end
      end

      def secure_compare(a, b)
        a = a.to_s
        b = b.to_s
        return false if a.bytesize != b.bytesize
        a.bytes.zip(b.bytes).map { |x, y| x ^ y }.inject(0, :|).zero?
      end

      def json_body
        JSON.parse(request.body.read.to_s)
      rescue JSON::ParserError
        halt 400, { "Content-Type" => "application/json" },
             JSON.dump(error: "invalid_json")
      end
    end

    # ── Routes ──────────────────────────────────────────────────────
    get "/healthz" do
      content_type :json
      JSON.dump(status: "ok", service: "denchclaw-bridge", ts: Time.now.utc.iso8601)
    end

    post "/leads" do
      authenticated!

      payload = json_body
      unless payload.is_a?(Hash) && !payload["lead_email"].to_s.strip.empty?
        halt 422, { "Content-Type" => "application/json" },
             JSON.dump(error: "lead_email is required")
      end

      stdout, stderr, status = nil
      begin
        Timeout.timeout(TIMEOUT_SECS) do
          stdout, stderr, status = Open3.capture3(
            CRM_SCRIPT, stdin_data: JSON.dump(payload)
          )
        end
      rescue Timeout::Error
        halt 504, { "Content-Type" => "application/json" },
             JSON.dump(error: "script_timeout", seconds: TIMEOUT_SECS)
      end

      unless status.success?
        halt 500, { "Content-Type" => "application/json" },
             JSON.dump(error: "script_failed", detail: stderr.to_s[0, 500])
      end

      content_type :json
      stdout
    end

    # ── /circleback/match ───────────────────────────────────────────
    # Inputs:  { attendee_email, meeting_time, window_hours? }
    # Returns: { matched: bool, meeting?: <full record> }
    #
    # The Circleback CLI is OAuth'd to Carlos's account; the DenchClaw
    # host is the only place that combination of binary + tokens lives.
    # OpenSOP webhook step calls this from Fly via Tailscale Funnel.
    #
    # CLI quirk: `meetings --json` paginates by concatenating JSON arrays
    # rather than emitting a single envelope. We have to split the
    # concatenated `]\s*[` boundary and merge.
    post "/circleback/match" do
      authenticated!
      payload = json_body

      email_q = payload["attendee_email"].to_s.strip.downcase
      time_q  = payload["meeting_time"].to_s.strip
      window  = (payload["window_hours"] || 6).to_i.clamp(1, 48)

      if email_q.empty? || time_q.empty?
        halt 422, { "Content-Type" => "application/json" },
             JSON.dump(error: "attendee_email and meeting_time are required")
      end

      target_t = begin
        Time.parse(time_q)
      rescue ArgumentError
        halt 422, { "Content-Type" => "application/json" },
             JSON.dump(error: "meeting_time not parseable as ISO 8601")
      end

      # Day-window for the list query; we narrow further in-memory after.
      from_date = (target_t - 24 * 3600).utc.strftime("%Y-%m-%d")
      to_date   = (target_t + 24 * 3600).utc.strftime("%Y-%m-%d")

      meetings = circleback_meetings_in_window(from_date, to_date)

      # Filter: any attendee email matches (case-insensitive) AND createdAt
      # within ±window hours of the requested meeting_time. Sort by closest.
      window_secs = window * 3600
      candidates = meetings.select do |m|
        next false unless (m["attendees"] || []).any? { |a| a["email"].to_s.downcase == email_q }
        created = begin
          Time.parse(m["createdAt"].to_s)
        rescue ArgumentError
          next false
        end
        (created - target_t).abs <= window_secs
      end.sort_by { |m| (Time.parse(m["createdAt"]) - target_t).abs }

      if candidates.empty?
        content_type :json
        halt 200, JSON.dump(matched: false, searched_window_hours: window, candidates_in_day_window: meetings.size)
      end

      best_id = candidates.first["id"].to_s
      detail = circleback_meeting_read(best_id)

      content_type :json
      JSON.dump(
        matched: true,
        meeting_id: best_id,
        name: detail["name"],
        created_at: detail["createdAt"],
        duration_seconds: detail["duration"],
        url: detail["url"],
        ical_uid: detail["icalUid"],
        attendees: detail["attendees"] || [],
        notes: detail["notes"].to_s,
        action_items: detail["actionItems"] || [],
        insights: detail["insights"] || [],
        tags: detail["tags"] || [],
        candidates_count: candidates.size
      )
    end

    # ── Circleback CLI helpers ──────────────────────────────────────
    helpers do
      def circleback_meetings_in_window(from_date, to_date)
        cmd = [ CIRCLEBACK_CLI, "--json", "meetings", "--from", from_date, "--to", to_date ]
        stdout, stderr, status = begin
          Timeout.timeout(TIMEOUT_SECS) { Open3.capture3(*cmd) }
        rescue Timeout::Error
          halt 504, { "Content-Type" => "application/json" },
               JSON.dump(error: "circleback_cli_timeout", seconds: TIMEOUT_SECS)
        end

        unless status.success?
          halt 502, { "Content-Type" => "application/json" },
               JSON.dump(error: "circleback_cli_failed", detail: stderr.to_s[0, 500])
        end

        # Concatenated JSON arrays — one per page. Split on `]<ws>[` boundaries.
        parse_concatenated_arrays(stdout.to_s)
      end

      def circleback_meeting_read(meeting_id)
        cmd = [ CIRCLEBACK_CLI, "--json", "meetings", "read", meeting_id.to_s ]
        stdout, stderr, status = begin
          Timeout.timeout(TIMEOUT_SECS) { Open3.capture3(*cmd) }
        rescue Timeout::Error
          halt 504, { "Content-Type" => "application/json" },
               JSON.dump(error: "circleback_cli_timeout", seconds: TIMEOUT_SECS)
        end

        unless status.success?
          halt 502, { "Content-Type" => "application/json" },
               JSON.dump(error: "circleback_cli_failed", detail: stderr.to_s[0, 500])
        end

        # `meetings read` returns either a bare object or a one-element array.
        # parse_concatenated_arrays handles the array case; fall back to a direct
        # JSON.parse for the bare-object case (returns [] from concatenated parser).
        items = parse_concatenated_arrays(stdout.to_s)
        return items.first unless items.empty?

        begin
          parsed = JSON.parse(stdout.to_s)
          parsed.is_a?(Array) ? parsed.first : parsed
        rescue JSON::ParserError
          halt 502, { "Content-Type" => "application/json" },
               JSON.dump(error: "circleback_parse_failed")
        end
      end

      def parse_concatenated_arrays(raw)
        items = []
        depth = 0
        start = nil
        # Open3 returns ASCII-8BIT; force UTF-8 so each_char doesn't choke on em-dashes etc.
        raw = raw.dup.force_encoding("UTF-8")
        raw.each_char.with_index do |c, i|
          if c == "["
            start = i if depth.zero?
            depth += 1
          elsif c == "]"
            depth -= 1
            if depth.zero? && start
              chunk = raw[start..i]
              begin
                parsed = JSON.parse(chunk)
                items.concat(parsed) if parsed.is_a?(Array)
              rescue JSON::ParserError
                # skip malformed chunk; continue
              end
              start = nil
            end
          end
        end
        items
      end
    end

    # Everything else gets a clean 404. No directory listing, no leaks.
    not_found do
      content_type :json
      JSON.dump(error: "not_found")
    end

    error do
      content_type :json
      JSON.dump(error: "internal_error")
    end

    run! if __FILE__ == $PROGRAM_NAME
  end
end
