# frozen_string_literal: true

require "rails_helper"

# The throttle blocks in config/initializers/rack_attack.rb call
# `demo_throttle?` (which reads DEMO_MODE) each time a request is processed.
# That means the env var just needs to be set before requests fire — no
# precompilation concern.
#
# Rack::Attack uses Rails.cache as its backing store. In test the default is
# :null_store (counters never persist). We swap in an ActiveSupport::Cache::MemoryStore
# for the duration of these examples so counters actually accumulate.

RSpec.describe "Demo rate limiting", type: :request do
  # Swap Rack::Attack's cache store to a real memory store for the duration
  # of every example in this file, then reset counters between examples.
  around do |example|
    original_store = Rack::Attack.cache.store
    mem_store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.cache.store = mem_store
    example.run
  ensure
    mem_store.clear
    Rack::Attack.cache.store = original_store
  end

  before { Rack::Attack.cache.store.clear }

  # Restore DEMO_MODE after each example.
  around do |example|
    original_demo = ENV["DEMO_MODE"]
    example.run
  ensure
    original_demo.nil? ? ENV.delete("DEMO_MODE") : ENV["DEMO_MODE"] = original_demo
  end

  # ------------------------------------------------------------------
  # DEMO_MODE on — the 11th POST to /start must return 429
  # ------------------------------------------------------------------

  context "when DEMO_MODE is on" do
    before { ENV["DEMO_MODE"] = "true" }

    it "returns 429 on the 11th POST to /sop/:name/start (limit: 10/hour)" do
      # Fire 10 allowed requests. The response may be 401 / 404 / 422 — anything
      # the real controller returns is fine. We only care that rack-attack does NOT
      # intercept requests 1–10.
      10.times do
        post "/sop/customer-onboarding/start",
             params: { inputs: {} }.to_json,
             headers: { "Content-Type" => "application/json", "REMOTE_ADDR" => "1.2.3.4" },
             env: { "REMOTE_ADDR" => "1.2.3.4" }
        expect(response.status).not_to eq(429), "request #{_1 + 1} was unexpectedly rate-limited"
      end

      # The 11th request must be throttled.
      post "/sop/customer-onboarding/start",
           params: { inputs: {} }.to_json,
           headers: { "Content-Type" => "application/json", "REMOTE_ADDR" => "1.2.3.4" },
           env: { "REMOTE_ADDR" => "1.2.3.4" }

      expect(response.status).to eq(429)
      expect(response.body).to include("rate_limit")
    end
  end

  # ------------------------------------------------------------------
  # DEMO_MODE off — 11 requests all pass through the real controller
  # ------------------------------------------------------------------

  context "when DEMO_MODE is off" do
    before { ENV.delete("DEMO_MODE") }

    it "never returns 429 for 11 POSTs to /sop/:name/start" do
      11.times do
        post "/sop/customer-onboarding/start",
             params: { inputs: {} }.to_json,
             headers: { "Content-Type" => "application/json", "REMOTE_ADDR" => "1.2.3.5" },
             env: { "REMOTE_ADDR" => "1.2.3.5" }
        expect(response.status).not_to eq(429),
          "expected no rate-limit when DEMO_MODE is off, got 429 on request #{_1 + 1}"
      end
    end
  end
end
