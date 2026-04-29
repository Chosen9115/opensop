require "rails_helper"

RSpec.describe Opensop::CostRollup do
  describe ".call" do
    let(:now) { Time.zone.local(2026, 4, 29, 12, 0, 0) }

    context "with no LLM calls" do
      it "returns zeroed totals and a 31-entry zero-filled daily series" do
        result = described_class.call(now: now)

        expect(result.totals).to eq(
          spend_cents: 0, calls: 0, tokens_in: 0, tokens_out: 0
        )
        # Inclusive (start..end) of the 30-day window -> 31 day buckets.
        expect(result.daily.size).to eq(31)
        expect(result.daily).to all(include(cost_cents: 0))
        expect(result.top_steps).to eq([])
      end
    end

    context "with LLM calls inside and outside the window" do
      let(:instance) { create(:sop_instance, :running) }
      let(:step_a) { create(:sop_step, instance: instance, step_name: "draft_email") }
      let(:step_b) { create(:sop_step, instance: instance, step_name: "summarise") }
      let(:step_c) { create(:sop_step, instance: instance, step_name: "classify") }

      before do
        # Step A — two calls within window
        Sop::LlmCall.create!(step: step_a, model: "gpt-4o", prompt_hash: "a1",
                             attempt: 1, status: "succeeded",
                             input_tokens: 1000, output_tokens: 500,
                             cost_cents: 250, started_at: now - 2.days)
        Sop::LlmCall.create!(step: step_a, model: "gpt-4o", prompt_hash: "a2",
                             attempt: 2, status: "succeeded",
                             input_tokens: 800, output_tokens: 200,
                             cost_cents: 120, started_at: now - 5.days)

        # Step B — one call within window
        Sop::LlmCall.create!(step: step_b, model: "claude-3-5-sonnet", prompt_hash: "b1",
                             attempt: 1, status: "succeeded",
                             input_tokens: 4000, output_tokens: 1000,
                             cost_cents: 90, started_at: now - 10.days)

        # Step C — call outside window (should be excluded everywhere)
        Sop::LlmCall.create!(step: step_c, model: "gpt-4o", prompt_hash: "c1",
                             attempt: 1, status: "succeeded",
                             input_tokens: 9999, output_tokens: 9999,
                             cost_cents: 9999, started_at: now - 60.days)
      end

      it "sums totals only inside the 30-day window" do
        result = described_class.call(now: now)

        expect(result.totals).to eq(
          spend_cents: 250 + 120 + 90,
          calls: 3,
          tokens_in: 1000 + 800 + 4000,
          tokens_out: 500 + 200 + 1000
        )
      end

      it "produces a per-day series with non-zero buckets on the right days" do
        result = described_class.call(now: now)

        nonzero = result.daily.reject { |d| d[:cost_cents].zero? }
        expect(nonzero.map { |d| d[:cost_cents] }.sort).to eq([ 90, 120, 250 ])

        dates = nonzero.map { |d| d[:date] }
        expect(dates).to include(now.to_date - 2)
        expect(dates).to include(now.to_date - 5)
        expect(dates).to include(now.to_date - 10)
      end

      it "ranks top steps by cost descending and exposes step metadata" do
        result = described_class.call(now: now)

        expect(result.top_steps.size).to eq(2) # only A and B in window
        first = result.top_steps.first
        expect(first[:step_name]).to eq("draft_email")
        expect(first[:cost_cents]).to eq(250 + 120)
        expect(first[:calls]).to eq(2)
        expect(first[:model]).to eq("gpt-4o")
        expect(first[:instance_id]).to eq(instance.id.to_s)

        second = result.top_steps.last
        expect(second[:step_name]).to eq("summarise")
        expect(second[:cost_cents]).to eq(90)
        expect(second[:calls]).to eq(1)
      end

      it "caps top steps at 10" do
        # Add 12 more steps, each with a single call — total should still cap at 10.
        12.times do |i|
          extra_step = create(:sop_step, instance: instance, step_name: "extra_#{i}")
          Sop::LlmCall.create!(step: extra_step, model: "gpt-4o",
                               prompt_hash: "extra-#{i}", attempt: 1,
                               status: "succeeded",
                               input_tokens: 10, output_tokens: 5,
                               cost_cents: 1000 - i, started_at: now - 1.day)
        end

        result = described_class.call(now: now)
        expect(result.top_steps.size).to eq(described_class::TOP_STEPS_LIMIT)
      end
    end

    context "when the table is unavailable" do
      it "swallows ActiveRecord::StatementInvalid and returns zero rollups" do
        allow(Sop::LlmCall).to receive(:where)
          .and_raise(ActiveRecord::StatementInvalid.new("relation does not exist"))

        result = described_class.call

        expect(result.totals).to eq(
          spend_cents: 0, calls: 0, tokens_in: 0, tokens_out: 0
        )
        expect(result.daily.size).to be > 0
        expect(result.daily).to all(include(cost_cents: 0))
        expect(result.top_steps).to eq([])
      end
    end
  end
end
