# frozen_string_literal: true

require "rails_helper"

RSpec.describe Opensop::DemoMode do
  describe ".enabled?" do
    context "when DEMO_MODE is 'true'" do
      before { ENV["DEMO_MODE"] = "true" }
      after  { ENV.delete("DEMO_MODE") }

      it "returns true" do
        expect(described_class.enabled?).to be true
      end
    end

    context "when DEMO_MODE has varied casing and whitespace" do
      after { ENV.delete("DEMO_MODE") }

      it "returns true for 'True'" do
        ENV["DEMO_MODE"] = "True"
        expect(described_class.enabled?).to be true
      end

      it "returns true for ' true '" do
        ENV["DEMO_MODE"] = " true "
        expect(described_class.enabled?).to be true
      end

      it "returns true for 'TRUE'" do
        ENV["DEMO_MODE"] = "TRUE"
        expect(described_class.enabled?).to be true
      end
    end

    context "when DEMO_MODE is not 'true'" do
      after { ENV.delete("DEMO_MODE") }

      it "returns false for 'false'" do
        ENV["DEMO_MODE"] = "false"
        expect(described_class.enabled?).to be false
      end

      it "returns false for '0'" do
        ENV["DEMO_MODE"] = "0"
        expect(described_class.enabled?).to be false
      end

      it "returns false for empty string" do
        ENV["DEMO_MODE"] = ""
        expect(described_class.enabled?).to be false
      end

      it "returns false when unset" do
        ENV.delete("DEMO_MODE")
        expect(described_class.enabled?).to be false
      end
    end
  end

  describe ".api_token" do
    context "when DEMO_API_TOKEN is set" do
      before { ENV["DEMO_API_TOKEN"] = "custom-token-abc" }
      after  { ENV.delete("DEMO_API_TOKEN") }

      it "returns the env value" do
        expect(described_class.api_token).to eq("custom-token-abc")
      end
    end

    context "when DEMO_API_TOKEN is not set" do
      before { ENV.delete("DEMO_API_TOKEN") }

      it "returns the default token" do
        expect(described_class.api_token).to eq("demo-public-token-resets-daily")
      end
    end
  end

  describe "constants" do
    it "exposes RESET_SCHEDULE_CRON" do
      expect(Opensop::DemoMode::RESET_SCHEDULE_CRON).to eq("0 3 * * *")
    end

    it "exposes RESET_SCHEDULE_HUMAN" do
      expect(Opensop::DemoMode::RESET_SCHEDULE_HUMAN).to eq("daily at 3:00 UTC")
    end
  end
end
