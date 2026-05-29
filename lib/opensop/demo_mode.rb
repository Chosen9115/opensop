# frozen_string_literal: true

module Opensop
  module DemoMode
    module_function

    # True when DEMO_MODE env var is set to "true" (case-insensitive, trimmed).
    # Anything else (unset, "false", "0", empty, "True " — yes trimmed) is false.
    def enabled?
      ENV.fetch("DEMO_MODE", "").to_s.strip.downcase == "true"
    end

    # The public API token announced on the demo homepage.
    #
    # Prefers OPENSOP_API_TOKEN — the same env var Sop::ApplicationController
    # uses for /sop/* auth — so a single secret powers both auth and the
    # value displayed to visitors. Falls back to DEMO_API_TOKEN (kept for
    # local dev convenience) and finally a stable default so dev never crashes.
    def api_token
      ENV.fetch("OPENSOP_API_TOKEN") do
        ENV.fetch("DEMO_API_TOKEN", "demo-public-token-resets-daily")
      end
    end

    # The default reset cron schedule, exposed as a single constant so the
    # banner UI and the recurring job spec can reference it without drift.
    RESET_SCHEDULE_CRON  = "0 3 * * *"
    RESET_SCHEDULE_HUMAN = "daily at 3:00 UTC"
  end
end
