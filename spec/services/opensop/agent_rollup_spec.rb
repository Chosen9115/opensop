require "rails_helper"

RSpec.describe Opensop::AgentRollup do
  describe ".call" do
    let(:now) { Time.zone.local(2026, 4, 29, 12, 0, 0) }

    context "with no LLM calls" do
      it "returns an empty agents list and zeroed totals" do
        result = described_class.call(now: now)

        expect(result.agents).to eq([])
        expect(result.totals).to eq(
          models_count: 0, total_calls: 0, total_cost_cents: 0
        )
      end
    end

    context "with mixed-status calls inside and outside the 30-day window" do
      let(:instance) { create(:sop_instance, :running) }
      # Each call needs its own (step_id, attempt) pair due to a unique index
      # on sop_llm_calls. Confidence values mean: gpt-4o avg = (0.9+0.9+0.7)/3.
      let(:step_a1) { create(:sop_step, instance: instance, step_name: "draft_email", confidence: 0.9) }
      let(:step_a2) { create(:sop_step, instance: instance, step_name: "draft_email_2", confidence: 0.9) }
      let(:step_b1) { create(:sop_step, instance: instance, step_name: "summarise", confidence: 0.7) }
      let(:step_c) { create(:sop_step, instance: instance, step_name: "classify") }
      let(:step_b2) { create(:sop_step, instance: instance, step_name: "summarise_2", confidence: 0.7) }
      let(:step_old) { create(:sop_step, instance: instance, step_name: "old", confidence: 0.5) }

      before do
        # gpt-4o — 4 calls inside window: 3 succeeded, 1 errored
        Sop::LlmCall.create!(step: step_a1, model: "gpt-4o", prompt_hash: "a1",
                             attempt: 1, status: "succeeded",
                             input_tokens: 1000, output_tokens: 500,
                             cost_cents: 250, started_at: now - 2.days)
        Sop::LlmCall.create!(step: step_a2, model: "gpt-4o", prompt_hash: "a2",
                             attempt: 1, status: "succeeded",
                             input_tokens: 800, output_tokens: 200,
                             cost_cents: 120, started_at: now - 5.days)
        Sop::LlmCall.create!(step: step_b1, model: "gpt-4o", prompt_hash: "a3",
                             attempt: 1, status: "succeeded",
                             input_tokens: 400, output_tokens: 100,
                             cost_cents: 60, started_at: now - 7.days)
        Sop::LlmCall.create!(step: step_c, model: "gpt-4o", prompt_hash: "a4",
                             attempt: 1, status: "errored",
                             input_tokens: 0, output_tokens: 0,
                             cost_cents: 0, started_at: now - 6.days)

        # claude-3-5-sonnet — 2 calls inside window: 1 succeeded, 1 schema_failed
        # Both attached to step_b1 (attempt 2) and step_b2 (attempt 1).
        Sop::LlmCall.create!(step: step_b1, model: "claude-3-5-sonnet", prompt_hash: "b1",
                             attempt: 2, status: "succeeded",
                             input_tokens: 4000, output_tokens: 1000,
                             cost_cents: 90, started_at: now - 10.days)
        Sop::LlmCall.create!(step: step_b2, model: "claude-3-5-sonnet", prompt_hash: "b2",
                             attempt: 1, status: "schema_failed",
                             input_tokens: 100, output_tokens: 50,
                             cost_cents: 5, started_at: now - 11.days)

        # outside-window call — must be excluded everywhere
        Sop::LlmCall.create!(step: step_old, model: "gpt-3.5-turbo", prompt_hash: "old1",
                             attempt: 1, status: "succeeded",
                             input_tokens: 9999, output_tokens: 9999,
                             cost_cents: 9999, started_at: now - 60.days)
      end

      it "groups by model and orders by total_calls descending" do
        result = described_class.call(now: now)

        models = result.agents.map { |a| a[:model] }
        expect(models).to eq([ "gpt-4o", "claude-3-5-sonnet" ])
        expect(result.agents.map { |a| a[:total_calls] }).to eq([ 4, 2 ])
      end

      it "computes per-model success/error counts and rates" do
        result = described_class.call(now: now)

        gpt = result.agents.find { |a| a[:model] == "gpt-4o" }
        expect(gpt[:total_calls]).to eq(4)
        expect(gpt[:succeeded]).to eq(3)
        expect(gpt[:errored]).to eq(1) # 1 errored, 0 schema_failed
        expect(gpt[:success_rate]).to be_within(0.001).of(0.75)

        claude = result.agents.find { |a| a[:model] == "claude-3-5-sonnet" }
        expect(claude[:total_calls]).to eq(2)
        expect(claude[:succeeded]).to eq(1)
        expect(claude[:errored]).to eq(1) # combines errored + schema_failed
        expect(claude[:success_rate]).to be_within(0.001).of(0.5)
      end

      it "sums cost and tokens per model, in window only" do
        result = described_class.call(now: now)

        gpt = result.agents.find { |a| a[:model] == "gpt-4o" }
        expect(gpt[:cost_cents]).to eq(250 + 120 + 60 + 0)
        expect(gpt[:tokens_in]).to eq(1000 + 800 + 400 + 0)
        expect(gpt[:tokens_out]).to eq(500 + 200 + 100 + 0)

        claude = result.agents.find { |a| a[:model] == "claude-3-5-sonnet" }
        expect(claude[:cost_cents]).to eq(90 + 5)
        expect(claude[:tokens_in]).to eq(4000 + 100)
        expect(claude[:tokens_out]).to eq(1000 + 50)
      end

      it "averages confidence from joined steps with non-null confidence" do
        result = described_class.call(now: now)

        # gpt-4o calls hit step_a (0.9 x2), step_b (0.7), step_c (nil — excluded)
        # avg = (0.9 + 0.9 + 0.7) / 3 = 0.8333...
        gpt = result.agents.find { |a| a[:model] == "gpt-4o" }
        expect(gpt[:avg_confidence]).to be_within(0.01).of(0.8333)

        # claude calls both hit step_b (0.7) -> avg = 0.7
        claude = result.agents.find { |a| a[:model] == "claude-3-5-sonnet" }
        expect(claude[:avg_confidence]).to be_within(0.01).of(0.7)
      end

      it "exposes last_used_at as the most recent started_at per model" do
        result = described_class.call(now: now)

        gpt = result.agents.find { |a| a[:model] == "gpt-4o" }
        expect(gpt[:last_used_at]).to be_within(1.second).of(now - 2.days)

        claude = result.agents.find { |a| a[:model] == "claude-3-5-sonnet" }
        expect(claude[:last_used_at]).to be_within(1.second).of(now - 10.days)
      end

      it "excludes out-of-window models entirely" do
        result = described_class.call(now: now)
        models = result.agents.map { |a| a[:model] }
        expect(models).not_to include("gpt-3.5-turbo")
      end

      it "rolls up totals across all in-window agents" do
        result = described_class.call(now: now)

        expect(result.totals[:models_count]).to eq(2)
        expect(result.totals[:total_calls]).to eq(4 + 2)
        expect(result.totals[:total_cost_cents]).to eq(250 + 120 + 60 + 0 + 90 + 5)
      end
    end

    context "when calls reference steps with no confidence" do
      let(:instance) { create(:sop_instance, :running) }
      let(:step) { create(:sop_step, instance: instance, confidence: nil) }

      before do
        Sop::LlmCall.create!(step: step, model: "gpt-4o", prompt_hash: "n1",
                             attempt: 1, status: "succeeded",
                             input_tokens: 100, output_tokens: 50,
                             cost_cents: 10, started_at: 1.day.ago)
      end

      it "reports avg_confidence as 0.0" do
        result = described_class.call

        gpt = result.agents.find { |a| a[:model] == "gpt-4o" }
        expect(gpt).not_to be_nil
        expect(gpt[:avg_confidence]).to eq(0.0)
      end
    end

    context "when the table is unavailable" do
      it "swallows ActiveRecord::StatementInvalid and returns empty rollups" do
        allow(Sop::LlmCall).to receive(:where)
          .and_raise(ActiveRecord::StatementInvalid.new("relation does not exist"))

        result = described_class.call

        expect(result.agents).to eq([])
        expect(result.totals).to eq(
          models_count: 0, total_calls: 0, total_cost_cents: 0
        )
      end
    end
  end
end
