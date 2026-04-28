require 'rails_helper'

RSpec.describe Opensop::InstanceExecutor do
  describe ".start" do
    context "with a notification-only process" do
      let(:process) do
        build_process(
          name: "notif-proc",
          inputs: [ { "name" => "email", "type" => "string", "required" => true } ],
          outputs: [ { "name" => "notified", "from" => "steps.send-email.outputs.notified" } ],
          steps: [
            {
              "id" => "send-email",
              "name" => "Send",
              "type" => "notification",
              "inputs" => [ { "name" => "to", "from" => "process.inputs.email" } ],
              "outputs" => [ { "name" => "notified", "type" => "boolean" } ]
            }
          ]
        )
      end

      it "creates an instance, step rows, and a started event" do
        instance = described_class.start(process: process, inputs: { "email" => "ada@example.com" })

        expect(instance).to be_persisted
        expect(instance.steps.count).to eq(1)
        expect(instance.events.where(event_type: "instance.started")).to exist
      end

      it "advances through to completion for a synchronous step" do
        instance = described_class.start(process: process, inputs: { "email" => "ada@example.com" })

        aggregate_failures do
          expect(instance.reload.state).to eq("completed")
          expect(instance.steps.first.state).to eq("completed")
          expect(instance.outputs).to include("notified" => true)
          expect(instance.events.pluck(:event_type))
            .to include("instance.started", "step.started", "step.completed", "instance.completed")
        end
      end

      it "raises InvalidInputs when a required input is missing" do
        expect { described_class.start(process: process, inputs: {}) }
          .to raise_error(described_class::InvalidInputs, /missing required input/)
      end
    end

    context "with a form step" do
      let(:process) do
        build_process(
          name: "form-proc",
          steps: [
            { "id" => "collect", "name" => "Collect", "type" => "form" }
          ]
        )
      end

      it "pauses at the form step in sub_state=waiting_for_input" do
        instance = described_class.start(process: process, inputs: { "alpha" => "ok" })

        step = instance.steps.first
        expect(step.state).to eq("active")
        expect(step.sub_state).to eq("waiting_for_input")
        expect(instance.reload.state).to eq("running")
      end
    end
  end

  describe ".submit_step" do
    let(:process) do
      build_process(
        name: "form-submit-proc",
        inputs: [ { "name" => "alpha", "type" => "string", "required" => true } ],
        outputs: [ { "name" => "record", "from" => "steps.collect.outputs.record" } ],
        steps: [
          {
            "id" => "collect",
            "name" => "Collect",
            "type" => "form",
            "outputs" => [ { "name" => "record", "type" => "object" } ]
          },
          {
            "id" => "notify",
            "name" => "Notify",
            "type" => "notification"
          }
        ]
      )
    end

    it "completes a waiting form step and advances the instance" do
      instance = described_class.start(process: process, inputs: { "alpha" => "ok" })

      described_class.submit_step(
        instance: instance,
        step_id: "collect",
        outputs: { "record" => { "legal_name" => "Acme" } },
        decided_by: "user@example.com"
      )

      instance.reload
      collect = instance.steps.find_by(step_id: "collect")
      notify  = instance.steps.find_by(step_id: "notify")

      aggregate_failures do
        expect(collect.state).to eq("completed")
        expect(collect.decided_by).to eq("user@example.com")
        expect(notify.state).to eq("completed")
        expect(instance.state).to eq("completed")
        expect(instance.outputs).to include("record" => { "legal_name" => "Acme" })
      end
    end

    it "raises when the step is not in a submittable state" do
      process2 = build_process(
        name: "already-done-proc",
        steps: [ { "id" => "noop", "name" => "Noop", "type" => "notification" } ]
      )
      instance = described_class.start(process: process2, inputs: { "alpha" => "x" })

      expect {
        described_class.submit_step(
          instance: instance, step_id: "noop",
          outputs: {}, decided_by: "system"
        )
      }.to raise_error(described_class::InvalidTransition)
    end
  end

  describe "condition handling" do
    let(:process) do
      build_process(
        name: "cond-proc",
        inputs: [ { "name" => "alpha", "type" => "string", "required" => true } ],
        steps: [
          {
            "id" => "skipped",
            "name" => "Skipped",
            "type" => "notification",
            "condition" => "process.inputs.alpha == 'unreachable'"
          },
          {
            "id" => "always",
            "name" => "Always",
            "type" => "notification"
          }
        ]
      )
    end

    it "marks a step with a false condition as skipped" do
      instance = described_class.start(process: process, inputs: { "alpha" => "hello" })
      expect(instance.steps.find_by(step_id: "skipped").state).to eq("skipped")
      expect(instance.steps.find_by(step_id: "always").state).to eq("completed")
      expect(instance.reload.state).to eq("completed")
    end
  end

  describe ".cancel!" do
    let(:process) do
      build_process(
        name: "cancel-proc",
        steps: [ { "id" => "wait", "name" => "Wait", "type" => "form" } ]
      )
    end

    it "cancels an active instance, skips active steps, and emits events" do
      instance = described_class.start(process: process, inputs: { "alpha" => "x" })
      described_class.cancel!(instance, reason: "user quit")
      instance.reload

      aggregate_failures do
        expect(instance.state).to eq("cancelled")
        expect(instance.steps.first.state).to eq("skipped")
        expect(instance.events.pluck(:event_type)).to include("instance.cancelled", "step.skipped")
      end
    end
  end

  describe "process outputs with required_if" do
    # Process: one form step with outputs {status, rejection_reason}.
    # Process-level rejection_reason is gated by required_if "status == 'rejected'".
    let(:process) do
      build_process(
        name: "required-if-proc",
        inputs: [ { "name" => "alpha", "type" => "string", "required" => true } ],
        outputs: [
          { "name" => "status", "type" => "string",
            "from" => "steps.decide.outputs.status" },
          { "name" => "rejection_reason", "type" => "string",
            "from" => "steps.decide.outputs.rejection_reason",
            "required_if" => "status == 'rejected'" }
        ],
        steps: [
          {
            "id" => "decide",
            "name" => "Decide",
            "type" => "form",
            "outputs" => [
              { "name" => "status", "type" => "string" },
              { "name" => "rejection_reason", "type" => "string",
                "required_if" => "status == 'rejected'" }
            ]
          }
        ]
      )
    end

    it "omits rejection_reason from final outputs on the approved path" do
      instance = described_class.start(process: process, inputs: { "alpha" => "ok" })

      described_class.submit_step(
        instance: instance,
        step_id: "decide",
        # No rejection_reason — validate_outputs! should accept because
        # required_if ("status == 'rejected'") is false.
        outputs: { "status" => "approved" }
      )

      instance.reload
      aggregate_failures do
        expect(instance.state).to eq("completed")
        expect(instance.outputs).to include("status" => "approved")
        expect(instance.outputs).not_to have_key("rejection_reason")
      end
    end

    it "includes rejection_reason in final outputs on the rejected path" do
      instance = described_class.start(process: process, inputs: { "alpha" => "ok" })

      described_class.submit_step(
        instance: instance,
        step_id: "decide",
        outputs: { "status" => "rejected", "rejection_reason" => "missing docs" }
      )

      instance.reload
      aggregate_failures do
        expect(instance.state).to eq("completed")
        expect(instance.outputs).to include(
          "status" => "rejected",
          "rejection_reason" => "missing docs"
        )
      end
    end

    it "raises InvalidInputs when a required_if-gated output is required but missing" do
      instance = described_class.start(process: process, inputs: { "alpha" => "ok" })

      expect {
        described_class.submit_step(
          instance: instance,
          step_id: "decide",
          # status == rejected triggers required_if — rejection_reason required.
          outputs: { "status" => "rejected" }
        )
      }.to raise_error(described_class::InvalidInputs, /rejection_reason/)
    end
  end

  describe "exit_when:" do
    # Two-step process: gate (form) -> notify (notification).
    # The gate carries `exit_when: outputs.score < 0.4` and literal
    # `exit_outputs: { outcome: "rejected" }`. Form steps let us inject a
    # specific `score` deterministically via submit_step.
    let(:exit_process) do
      build_process(
        name: "exit-when-proc",
        inputs: [ { "name" => "alpha", "type" => "string", "required" => true } ],
        outputs: [
          { "name" => "outcome", "from" => "steps.gate.outputs.outcome" }
        ],
        steps: [
          {
            "id" => "gate",
            "name" => "Gate",
            "type" => "form",
            "outputs" => [ { "name" => "score", "type" => "number" } ],
            "exit_when" => "outputs.score < 0.4",
            "exit_outputs" => { "outcome" => "rejected" }
          },
          {
            "id" => "notify",
            "name" => "Notify",
            "type" => "notification"
          }
        ]
      )
    end

    it "terminates the process and never runs subsequent steps when the predicate is true" do
      instance = described_class.start(process: exit_process, inputs: { "alpha" => "ok" })

      described_class.submit_step(
        instance: instance,
        step_id: "gate",
        outputs: { "score" => 0.3 }
      )

      instance.reload
      gate   = instance.steps.find_by(step_id: "gate")
      notify = instance.steps.find_by(step_id: "notify")

      aggregate_failures do
        expect(instance.state).to eq("completed")
        expect(instance.outputs).to include("outcome" => "rejected")
        expect(gate.state).to eq("completed")
        # Notify never advanced — the engine returned before reaching it.
        expect(notify.state).to eq("pending")
        expect(instance.events.where(event_type: "instance.exited_early")).to exist
        expect(instance.events.where(event_type: "step.completed",
                                     step_id: "notify")).not_to exist
      end
    end

    it "emits an instance.exited_early event whose data carries the step_id and exit_outputs" do
      instance = described_class.start(process: exit_process, inputs: { "alpha" => "ok" })
      described_class.submit_step(instance: instance, step_id: "gate",
                                  outputs: { "score" => 0.1 })

      event = instance.reload.events.find_by(event_type: "instance.exited_early")
      expect(event).to be_present
      expect(event.data).to include("step_id" => "gate")
      expect(event.data["exit_outputs"]).to include("outcome" => "rejected")
    end

    it "continues normal advancement when the predicate is false" do
      instance = described_class.start(process: exit_process, inputs: { "alpha" => "ok" })

      described_class.submit_step(
        instance: instance,
        step_id: "gate",
        outputs: { "score" => 0.7 }
      )

      instance.reload
      notify = instance.steps.find_by(step_id: "notify")

      aggregate_failures do
        expect(instance.state).to eq("completed")
        expect(notify.state).to eq("completed")
        expect(instance.events.where(event_type: "instance.exited_early")).not_to exist
      end
    end

    it "merges exit_outputs into existing instance.outputs rather than replacing them" do
      # Pre-populate the instance with prior outputs (simulating earlier
      # state collected before the gate ran). exit_outputs must merge in.
      instance = described_class.start(process: exit_process, inputs: { "alpha" => "ok" })
      instance.update!(outputs: { "prior_key" => "prior_value" })

      described_class.submit_step(
        instance: instance,
        step_id: "gate",
        outputs: { "score" => 0.2 }
      )

      instance.reload
      aggregate_failures do
        expect(instance.outputs).to include(
          "prior_key" => "prior_value",
          "outcome"   => "rejected"
        )
      end
    end

    it "treats an exit_when expression referencing a missing output as falsy and continues" do
      # ConditionEvaluator's documented semantics: an unresolved reference
      # returns nil; numeric comparisons against nil are false (safe_compare).
      # So `outputs.nonexistent < 0.4` evaluates false and the process
      # continues normally rather than exiting or raising.
      proc_with_bad_ref = build_process(
        name: "exit-when-missing-ref",
        inputs: [ { "name" => "alpha", "type" => "string", "required" => true } ],
        outputs: [ { "name" => "outcome", "from" => "steps.gate.outputs.outcome" } ],
        steps: [
          {
            "id" => "gate",
            "name" => "Gate",
            "type" => "form",
            "outputs" => [ { "name" => "score", "type" => "number" } ],
            "exit_when" => "outputs.nonexistent < 0.4",
            "exit_outputs" => { "outcome" => "rejected" }
          },
          { "id" => "notify", "name" => "Notify", "type" => "notification" }
        ]
      )

      instance = described_class.start(process: proc_with_bad_ref,
                                       inputs: { "alpha" => "ok" })
      described_class.submit_step(instance: instance, step_id: "gate",
                                  outputs: { "score" => 0.5 })

      instance.reload
      aggregate_failures do
        expect(instance.events.where(event_type: "instance.exited_early")).not_to exist
        expect(instance.steps.find_by(step_id: "notify").state).to eq("completed")
        expect(instance.state).to eq("completed")
      end
    end
  end

  describe ".try_exit_early! (public extension point)" do
    # Used by the loop executor to honor exit_when on body steps without
    # routing through advance!. Verifies the contract: returns :continue
    # when the predicate is false / absent, returns :exited and terminates
    # the instance when the predicate is true.
    let(:instance) do
      proc_rec = build_process(
        name: "try-exit-helper-proc",
        steps: [ { "id" => "noop", "name" => "Noop", "type" => "notification" } ]
      )
      Sop::Instance.create!(
        process: proc_rec,
        process_name: proc_rec.name,
        process_version: proc_rec.version,
        state: "running",
        inputs: {},
        outputs: { "preserved" => "value" },
        metadata: {}
      )
    end

    let(:step) do
      instance.steps.create!(
        step_id: "gate", step_name: "Gate", step_type: "form",
        state: "completed", inputs: {}, outputs: { "score" => 0.2 },
        position: 1, attempt: 1
      )
    end

    it "returns :continue when no exit_when is present" do
      result = described_class.try_exit_early!(step, { "id" => "gate" }, instance)
      expect(result).to eq(:continue)
      expect(instance.reload.state).to eq("running")
    end

    it "returns :exited and completes the instance when the predicate is true" do
      definition = {
        "id" => "gate",
        "exit_when" => "outputs.score < 0.4",
        "exit_outputs" => { "outcome" => "rejected" }
      }

      result = described_class.try_exit_early!(step, definition, instance)

      instance.reload
      aggregate_failures do
        expect(result).to eq(:exited)
        expect(instance.state).to eq("completed")
        expect(instance.outputs).to include(
          "preserved" => "value",
          "outcome"   => "rejected"
        )
      end
    end
  end

  describe "automated step failure (missing script)" do
    let(:process) do
      build_process(
        name: "bad-automated-proc",
        steps: [
          {
            "id" => "run-it",
            "name" => "Run",
            "type" => "automated",
            "run" => "/tmp/definitely/not/a/real/script-#{SecureRandom.hex(4)}.rb"
          }
        ]
      )
    end

    it "fails the step and transitions the instance to failed" do
      instance = described_class.start(process: process, inputs: { "alpha" => "ok" })
      instance.reload

      expect(instance.state).to eq("failed")
      failed_step = instance.steps.find_by(step_id: "run-it")
      expect(failed_step.state).to eq("failed")
      expect(failed_step.error).to match(/script not found/)
      expect(instance.events.where(event_type: "instance.failed")).to exist
    end
  end
end
