require "rails_helper"

RSpec.describe Opensop::MetricsRollup do
  describe ".call" do
    let(:now) { Time.zone.local(2026, 4, 29, 12, 0, 0) }

    context "with no data" do
      it "returns zeroed totals, empty per_process and zeroed step_health" do
        result = described_class.call(now: now)

        expect(result.totals).to eq(
          instances_started: 0,
          instances_completed: 0,
          instances_failed: 0,
          completion_rate: 0.0,
          avg_duration_seconds: 0.0,
          p95_duration_seconds: 0.0
        )
        expect(result.per_process).to eq([])
        expect(result.step_health).to eq(
          pending: 0, active: 0, completed: 0, failed: 0, skipped: 0
        )
      end
    end

    context "with mixed-state instances inside and outside the window" do
      let(:process_a) { create(:sop_process, name: "alpha", version: "1.0") }
      let(:process_b) { create(:sop_process, name: "beta",  version: "2.0") }

      before do
        # In-window completed (alpha) — duration ~120s
        create(:sop_instance,
               process: process_a, process_name: "alpha", process_version: "1.0",
               state: "completed",
               created_at: now - 4.hours,
               started_at: now - 4.hours,
               completed_at: now - 4.hours + 120.seconds,
               updated_at: now - 4.hours + 120.seconds)

        # In-window completed (alpha) — duration ~600s (will be the long tail)
        create(:sop_instance,
               process: process_a, process_name: "alpha", process_version: "1.0",
               state: "completed",
               created_at: now - 3.hours,
               started_at: now - 3.hours,
               completed_at: now - 3.hours + 600.seconds,
               updated_at: now - 3.hours + 600.seconds)

        # In-window failed (alpha)
        create(:sop_instance,
               process: process_a, process_name: "alpha", process_version: "1.0",
               state: "failed",
               created_at: now - 2.hours,
               updated_at: now - 2.hours + 30.seconds,
               completed_at: now - 2.hours + 30.seconds)

        # In-window running (beta) — counts as started + in_flight
        create(:sop_instance,
               process: process_b, process_name: "beta", process_version: "2.0",
               state: "running",
               created_at: now - 1.hour,
               started_at: now - 1.hour,
               updated_at: now - 1.hour)

        # OUTSIDE window — must be excluded from totals/per_process counts
        create(:sop_instance,
               process: process_a, process_name: "alpha", process_version: "1.0",
               state: "completed",
               created_at: now - 30.hours,
               started_at: now - 30.hours,
               completed_at: now - 30.hours + 9999.seconds,
               updated_at: now - 30.hours + 9999.seconds)

        # Out-of-window pending — pending instances should still surface as
        # in_flight (current snapshot), but NOT as `started` in window.
        create(:sop_instance,
               process: process_b, process_name: "beta", process_version: "2.0",
               state: "pending",
               created_at: now - 48.hours,
               updated_at: now - 48.hours)
      end

      it "counts only window instances for totals" do
        result = described_class.call(now: now)

        expect(result.totals[:instances_started]).to eq(4)
        expect(result.totals[:instances_completed]).to eq(2)
        expect(result.totals[:instances_failed]).to eq(1)
        # 2 / (2 + 1) = 0.6666...
        expect(result.totals[:completion_rate]).to be_within(0.001).of(2.0 / 3.0)
      end

      it "computes avg and p95 duration from window-completed instances only" do
        result = described_class.call(now: now)

        # Two completed in-window: ~120s and ~600s. Avg = 360, p95 = larger.
        expect(result.totals[:avg_duration_seconds]).to be_within(1.0).of(360.0)
        expect(result.totals[:p95_duration_seconds]).to be_within(1.0).of(600.0)
      end

      it "produces a per_process row per (name, version) ordered by started DESC" do
        result = described_class.call(now: now)

        expect(result.per_process.size).to eq(2)

        alpha = result.per_process.detect { |r| r[:process_name] == "alpha" }
        expect(alpha).to include(
          version: "1.0",
          started: 3,
          completed: 2,
          failed: 1
        )

        beta = result.per_process.detect { |r| r[:process_name] == "beta" }
        expect(beta).to include(
          version: "2.0",
          started: 1,
          completed: 0,
          failed: 0
        )
        # Beta has both an in-window running AND an out-of-window pending —
        # both should count toward the current `in_flight` snapshot.
        expect(beta[:in_flight]).to eq(2)

        # Ordered by started DESC: alpha (3) > beta (1)
        expect(result.per_process.first[:process_name]).to eq("alpha")
      end
    end

    context "step_health snapshot" do
      let(:instance) { create(:sop_instance, :running) }

      before do
        create(:sop_step, instance: instance, state: "pending",   step_id: "s-p", position: 1)
        create(:sop_step, instance: instance, state: "active",    step_id: "s-a", position: 2)
        create(:sop_step, instance: instance, state: "completed", step_id: "s-c", position: 3)
        create(:sop_step, instance: instance, state: "completed", step_id: "s-c2", position: 4)
        create(:sop_step, instance: instance, state: "failed",    step_id: "s-f", position: 5)
        create(:sop_step, instance: instance, state: "skipped",   step_id: "s-sk", position: 6)
      end

      it "rolls up current step counts by state across all time" do
        result = described_class.call(now: now)

        expect(result.step_health).to eq(
          pending: 1, active: 1, completed: 2, failed: 1, skipped: 1
        )
      end
    end

    context "when an underlying table is unavailable" do
      it "swallows ActiveRecord::StatementInvalid and returns zero rollups" do
        allow(Sop::Instance).to receive(:where)
          .and_raise(ActiveRecord::StatementInvalid.new("relation does not exist"))
        allow(Sop::Step).to receive(:group)
          .and_raise(ActiveRecord::StatementInvalid.new("relation does not exist"))

        result = described_class.call

        expect(result.totals).to include(
          instances_started: 0,
          instances_completed: 0,
          instances_failed: 0,
          completion_rate: 0.0,
          avg_duration_seconds: 0.0,
          p95_duration_seconds: 0.0
        )
        expect(result.per_process).to eq([])
        expect(result.step_health).to eq(
          pending: 0, active: 0, completed: 0, failed: 0, skipped: 0
        )
      end
    end
  end
end
