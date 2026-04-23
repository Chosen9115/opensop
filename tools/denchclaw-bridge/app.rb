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
require "json"
require "open3"
require "timeout"

module DenchClawBridge
  class App < Sinatra::Base
    # ── Config ──────────────────────────────────────────────────────
    TOKEN          = ENV["DENCHCLAW_BRIDGE_TOKEN"].to_s.freeze
    CRM_SCRIPT     = ENV["DENCHCLAW_BRIDGE_SCRIPT"].to_s.freeze
    TIMEOUT_SECS   = (ENV["DENCHCLAW_BRIDGE_TIMEOUT"] || "30").to_i

    configure do
      set :show_exceptions, false
      set :raise_errors, false
      set :logging, true

      # Rack::Protection's HostAuthorization rejects any Host header not in
      # its allowlist. We're reached via Tailscale Funnel (*.ts.net) — that's
      # intentional traffic. Bearer token on /leads is the real auth.
      # `disable :protection` is ignored for HostAuthorization in Sinatra 4.x,
      # so bypass it with an explicit allow-all lambda.
      set :protection, host_authorization: { allow_if: ->(_env) { true } }

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
