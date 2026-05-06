# frozen_string_literal: true

require "rails_helper"

RSpec.describe Demo::ResetJob do
  around do |example|
    original = ENV["DEMO_MODE"]
    example.run
  ensure
    original.nil? ? ENV.delete("DEMO_MODE") : ENV["DEMO_MODE"] = original
  end

  # ------------------------------------------------------------------
  # Queue registration
  # ------------------------------------------------------------------

  it "is enqueued on the :default queue" do
    expect(described_class.new.queue_name).to eq("default")
  end

  # ------------------------------------------------------------------
  # DEMO_MODE off — no-op
  # ------------------------------------------------------------------

  context "when DEMO_MODE is off" do
    before { ENV.delete("DEMO_MODE") }

    it "does not delete any Sop::Instance rows" do
      create(:sop_instance)
      expect { described_class.new.perform }.not_to change { Sop::Instance.count }
    end

    it "does not write to the DB at all" do
      expect(Sop::Instance).not_to receive(:delete_all)
      described_class.new.perform
    end
  end

  # ------------------------------------------------------------------
  # DEMO_MODE on
  # ------------------------------------------------------------------

  context "when DEMO_MODE is on" do
    before { ENV["DEMO_MODE"] = "true" }

    it "deletes all Sop::Instance rows" do
      create_list(:sop_instance, 3)
      expect { described_class.new.perform }.to change { Sop::Instance.count }.to(0)
    end

    it "does not remove process definitions" do
      # SeedLoader will add processes; we just need at least one going in.
      create(:sop_process)
      process_count_before = Sop::Process.count

      described_class.new.perform

      expect(Sop::Process.count).to be >= process_count_before
    end

    it "re-seeds processes after clearing instances" do
      expect(Demo::SeedLoader).to receive(:call).and_call_original
      described_class.new.perform
    end
  end
end
