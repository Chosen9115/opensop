# frozen_string_literal: true

module Demo
  # Idempotent seed loader for the public demo deployment.
  #
  # Loads all example process definitions from `processes/examples/` and
  # confirms the demo API token is configured, logging a clear message for
  # operators. Designed to run safely in two contexts:
  #
  #   1. `db:seed` — via the hook at the bottom of db/seeds.rb
  #   2. `Demo::ResetJob` — as part of the nightly 3:00 UTC data reset
  #
  # No-op when `Opensop::DemoMode.enabled?` is false, so this is safe to
  # deploy in non-demo environments without setting any extra env vars.
  #
  # Returns a Result struct with :processes_loaded and :token_configured so
  # callers and specs can assert on outcomes without parsing log output.
  #
  # Note on ApiToken: OpenSOP authenticates /sop/* requests via the
  # `OPENSOP_API_TOKEN` environment variable (see Sop::ApplicationController).
  # There is no ApiToken ActiveRecord model. The demo token is wired by
  # setting OPENSOP_API_TOKEN=<Opensop::DemoMode.api_token> in the deployment
  # environment. This loader validates that the env var matches and logs a
  # clear warning when it does not, so operators catch mismatches early.
  module SeedLoader
    Result = Struct.new(:processes_loaded, :token_configured, keyword_init: true)

    module_function

    def call
      unless Opensop::DemoMode.enabled?
        Rails.logger.info("[demo-seed] skipped — DEMO_MODE not enabled")
        return Result.new(processes_loaded: 0, token_configured: false)
      end

      # Confirm the API token env var is set and matches the expected demo token.
      # Auth is env-based; this is a configuration check, not a DB write.
      expected_token = Opensop::DemoMode.api_token
      actual_token   = ENV.fetch("OPENSOP_API_TOKEN", "").strip
      token_ok = actual_token == expected_token

      unless token_ok
        Rails.logger.warn(
          "[demo-seed] OPENSOP_API_TOKEN does not match DEMO_API_TOKEN. " \
          "Set OPENSOP_API_TOKEN=#{expected_token} (or set DEMO_API_TOKEN to match OPENSOP_API_TOKEN)."
        )
      end

      # Load process definitions scoped to processes/examples/ ONLY.
      # Passing examples_path as root means Registry.load_all globs
      # processes/examples/**/*.sop.yaml — private subdirectories such as
      # processes/coba/ are never touched.
      examples_path = Rails.root.join("processes", "examples")
      loaded = Opensop::Registry.load_all(examples_path)

      Rails.logger.info(
        "[demo-seed] loaded #{loaded.size} processes, " \
        "demo token #{token_ok ? 'ready' : 'MISMATCH — check env vars'}"
      )

      Result.new(processes_loaded: loaded.size, token_configured: token_ok)
    end
  end
end
