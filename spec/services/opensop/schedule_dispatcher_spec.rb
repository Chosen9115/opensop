require "rails_helper"

RSpec.describe Opensop::ScheduleDispatcher do
  describe ".call" do
    let(:now) { Time.zone.local(2026, 4, 29, 12, 0, 0) }

    def stub_executor_returning(id: SecureRandom.uuid)
      instance = instance_double(Sop::Instance, id: id)
      allow(Opensop::InstanceExecutor).to receive(:start).and_return(instance)
      instance
    end

    context "with no due schedules" do
      it "returns a zero-result" do
        result = described_class.call(now: now)

        expect(result.dispatched_count).to eq(0)
        expect(result.skipped_count).to eq(0)
        expect(result.failures).to eq([])
      end
    end

    context "with a due schedule and a matching active process" do
      let!(:process) do
        create(:sop_process, name: "alpha", version: "1.0", status: "active")
      end

      let!(:schedule) do
        create(:sop_schedule,
               name: "Alpha hourly",
               process_name: "alpha",
               cron_expression: "0 * * * *",
               inputs: { "k" => "v" },
               next_run_at: now - 1.minute,
               last_status: nil,
               failure_count: 3)
      end

      it "starts an instance, marks success, and recomputes next_run_at" do
        instance = stub_executor_returning

        result = described_class.call(now: now)

        expect(Opensop::InstanceExecutor).to have_received(:start).with(
          process: process,
          inputs: { "k" => "v" },
          metadata: { source: "schedule", schedule_id: schedule.id }
        )

        schedule.reload
        expect(result.dispatched_count).to eq(1)
        expect(result.skipped_count).to eq(0)
        expect(result.failures).to eq([])
        expect(schedule.last_run_at).to be_within(1.second).of(now)
        expect(schedule.last_instance_id).to eq(instance.id)
        expect(schedule.last_status).to eq("success")
        expect(schedule.failure_count).to eq(0)
        expect(schedule.next_run_at).to be_present
        expect(schedule.next_run_at).to be > now
      end

      context "and there is a deprecated newer version of the same process" do
        let!(:newer_deprecated) do
          create(:sop_process, name: "alpha", version: "2.0", status: "deprecated")
        end

        it "selects the active row, ignoring deprecated/archived versions" do
          stub_executor_returning

          described_class.call(now: now)

          expect(Opensop::InstanceExecutor).to have_received(:start).with(
            hash_including(process: process)
          )
        end
      end
    end

    context "when no active process exists for the schedule's process_name" do
      let!(:schedule) do
        create(:sop_schedule,
               process_name: "missing-proc",
               cron_expression: "0 * * * *",
               next_run_at: now - 1.minute,
               failure_count: 0)
      end

      it "marks the schedule failed and records a process_not_found failure" do
        allow(Opensop::InstanceExecutor).to receive(:start)

        result = described_class.call(now: now)

        expect(Opensop::InstanceExecutor).not_to have_received(:start)
        expect(result.dispatched_count).to eq(0)
        expect(result.skipped_count).to eq(1)
        expect(result.failures.size).to eq(1)
        expect(result.failures.first.schedule_id).to eq(schedule.id)
        expect(result.failures.first.reason).to eq("process_not_found")

        schedule.reload
        expect(schedule.last_status).to eq("failed")
        expect(schedule.failure_count).to eq(1)
        expect(schedule.last_run_at).to be_within(1.second).of(now)
        expect(schedule.next_run_at).to be > now
      end
    end

    context "when the only matching process is archived (not active)" do
      before do
        create(:sop_process, name: "archived-proc", version: "1.0", status: "archived")
      end

      let!(:schedule) do
        create(:sop_schedule,
               process_name: "archived-proc",
               cron_expression: "0 * * * *",
               next_run_at: now - 1.minute)
      end

      it "treats it as process_not_found" do
        allow(Opensop::InstanceExecutor).to receive(:start)

        result = described_class.call(now: now)

        expect(result.skipped_count).to eq(1)
        expect(result.failures.first.reason).to eq("process_not_found")
        expect(schedule.reload.last_status).to eq("failed")
      end
    end

    context "when InstanceExecutor.start raises" do
      let!(:process) do
        create(:sop_process, name: "alpha", version: "1.0", status: "active")
      end

      let!(:schedule) do
        create(:sop_schedule,
               process_name: "alpha",
               cron_expression: "0 * * * *",
               next_run_at: now - 1.minute,
               failure_count: 2)
      end

      it "records the failure, increments failure_count, and recomputes next_run_at" do
        allow(Opensop::InstanceExecutor).to receive(:start)
          .and_raise(StandardError, "boom")

        result = described_class.call(now: now)

        expect(result.dispatched_count).to eq(0)
        expect(result.skipped_count).to eq(0)
        expect(result.failures.size).to eq(1)
        expect(result.failures.first.schedule_id).to eq(schedule.id)
        expect(result.failures.first.reason).to include("boom")

        schedule.reload
        expect(schedule.last_status).to eq("failed")
        expect(schedule.failure_count).to eq(3)
        expect(schedule.last_run_at).to be_within(1.second).of(now)
        expect(schedule.next_run_at).to be > now
      end
    end

    context "with a mix of due schedules — success, missing-process, and raising" do
      let!(:process_ok) { create(:sop_process, name: "ok", version: "1.0", status: "active") }
      let!(:process_boom) { create(:sop_process, name: "boom", version: "1.0", status: "active") }

      let!(:schedule_ok) do
        create(:sop_schedule, process_name: "ok",
               cron_expression: "0 * * * *",
               next_run_at: now - 5.minutes)
      end
      let!(:schedule_missing) do
        create(:sop_schedule, process_name: "ghost",
               cron_expression: "0 * * * *",
               next_run_at: now - 4.minutes)
      end
      let!(:schedule_boom) do
        create(:sop_schedule, process_name: "boom",
               cron_expression: "0 * * * *",
               next_run_at: now - 3.minutes)
      end

      it "dispatches the good one, fails the others, and tracks counts" do
        allow(Opensop::InstanceExecutor).to receive(:start) do |process:, **|
          if process.name == "boom"
            raise StandardError, "kaboom"
          else
            instance_double(Sop::Instance, id: SecureRandom.uuid)
          end
        end

        result = described_class.call(now: now)

        expect(result.dispatched_count).to eq(1)
        expect(result.skipped_count).to eq(1)
        expect(result.failures.size).to eq(2)

        reasons = result.failures.map(&:reason)
        expect(reasons).to include("process_not_found")
        expect(reasons.any? { |r| r.include?("kaboom") }).to be true

        expect(schedule_ok.reload.last_status).to eq("success")
        expect(schedule_missing.reload.last_status).to eq("failed")
        expect(schedule_boom.reload.last_status).to eq("failed")
      end
    end

    context "with a disabled schedule whose next_run_at is in the past" do
      let!(:process) { create(:sop_process, name: "alpha", version: "1.0", status: "active") }
      let!(:schedule) do
        create(:sop_schedule,
               process_name: "alpha",
               cron_expression: "0 * * * *",
               enabled: false,
               next_run_at: now - 1.hour)
      end

      it "is not picked up by the dispatcher" do
        allow(Opensop::InstanceExecutor).to receive(:start)

        result = described_class.call(now: now)

        expect(Opensop::InstanceExecutor).not_to have_received(:start)
        expect(result.dispatched_count).to eq(0)
        expect(result.skipped_count).to eq(0)
        expect(result.failures).to eq([])
        expect(schedule.reload.last_status).to be_nil
      end
    end
  end
end
