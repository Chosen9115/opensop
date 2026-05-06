# frozen_string_literal: true

require "rails_helper"

RSpec.describe Demo::SeedLoader do
  # Helper: ensure DEMO_MODE and OPENSOP_API_TOKEN are always restored.
  def with_env(vars)
    old = vars.transform_values { |_| ENV[_key = nil] }
    vars.each { |k, v| v.nil? ? ENV.delete(k.to_s) : ENV[k.to_s] = v }
    yield
  ensure
    vars.each_key { |k| old[k].nil? ? ENV.delete(k.to_s) : ENV[k.to_s] = old[k] }
  end

  # ------------------------------------------------------------------
  # Environment isolation via around blocks
  # ------------------------------------------------------------------

  around do |example|
    original_demo        = ENV["DEMO_MODE"]
    original_api_token   = ENV["OPENSOP_API_TOKEN"]
    original_demo_token  = ENV["DEMO_API_TOKEN"]
    example.run
  ensure
    original_demo.nil?       ? ENV.delete("DEMO_MODE")           : ENV["DEMO_MODE"]           = original_demo
    original_api_token.nil?  ? ENV.delete("OPENSOP_API_TOKEN")   : ENV["OPENSOP_API_TOKEN"]   = original_api_token
    original_demo_token.nil? ? ENV.delete("DEMO_API_TOKEN")      : ENV["DEMO_API_TOKEN"]      = original_demo_token
  end

  # ------------------------------------------------------------------
  # DEMO_MODE off
  # ------------------------------------------------------------------

  context "when DEMO_MODE is off" do
    before { ENV.delete("DEMO_MODE") }

    it "returns early without touching the DB" do
      expect { described_class.call }.not_to change { Sop::Process.count }
    end

    it "returns a Result with processes_loaded: 0" do
      result = described_class.call
      expect(result.processes_loaded).to eq(0)
    end

    it "returns a Result with token_configured: false" do
      result = described_class.call
      expect(result.token_configured).to be(false)
    end
  end

  # ------------------------------------------------------------------
  # DEMO_MODE on
  # ------------------------------------------------------------------

  context "when DEMO_MODE is on" do
    before { ENV["DEMO_MODE"] = "true" }

    it "loads at least 6 processes from processes/examples/" do
      result = described_class.call
      expect(result.processes_loaded).to be >= 6
    end

    it "persists the loaded processes in the DB" do
      expect { described_class.call }.to change { Sop::Process.count }.by_at_least(1)
    end

    it "is idempotent — calling twice does not duplicate processes" do
      described_class.call
      count_after_first = Sop::Process.count

      described_class.call
      count_after_second = Sop::Process.count

      expect(count_after_second).to eq(count_after_first)
    end

    context "when OPENSOP_API_TOKEN matches the demo token" do
      before do
        ENV["OPENSOP_API_TOKEN"] = Opensop::DemoMode.api_token
      end

      it "returns token_configured: true" do
        result = described_class.call
        expect(result.token_configured).to be(true)
      end
    end

    context "when OPENSOP_API_TOKEN does not match the demo token" do
      # `api_token` prefers OPENSOP_API_TOKEN then DEMO_API_TOKEN then a hardcoded default.
      # `actual_token` reads ENV["OPENSOP_API_TOKEN"] directly.
      # If OPENSOP_API_TOKEN is SET they are always equal (api_token == actual_token).
      # To force a mismatch: unset OPENSOP_API_TOKEN so api_token = DEMO_API_TOKEN
      # while actual_token = ENV.fetch("OPENSOP_API_TOKEN", "") = "". They differ.
      before do
        ENV["DEMO_API_TOKEN"] = "demo-expected-tok"
        ENV.delete("OPENSOP_API_TOKEN")
      end

      it "logs a warning containing 'OPENSOP_API_TOKEN does not match'" do
        expect(Rails.logger).to receive(:warn).with(
          a_string_including("OPENSOP_API_TOKEN does not match")
        )
        described_class.call
      end

      it "returns token_configured: false" do
        allow(Rails.logger).to receive(:warn)
        result = described_class.call
        expect(result.token_configured).to be(false)
      end
    end

    it "returns a Result struct with the correct keys" do
      result = described_class.call
      expect(result).to respond_to(:processes_loaded)
      expect(result).to respond_to(:token_configured)
    end
  end
end
