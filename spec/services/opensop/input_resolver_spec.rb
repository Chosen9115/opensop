require 'rails_helper'

RSpec.describe Opensop::InputResolver do
  let(:process) do
    build_process(
      name: "resolver-proc",
      steps: [ { "id" => "first", "name" => "First", "type" => "notification" } ]
    )
  end
  let(:instance) do
    create(:sop_instance,
           process: process,
           inputs: { "company" => "Acme" },
           metadata: { "deal_id" => "XYZ-1" })
  end
  let(:resolver) { described_class.new(instance: instance) }

  describe "#resolve" do
    it "resolves a literal value" do
      defn = { "inputs" => [ { "name" => "x", "value" => 42 } ] }
      expect(resolver.resolve(defn)).to eq({ "x" => 42 })
    end

    it "resolves process.inputs.<name>" do
      defn = { "inputs" => [ { "name" => "company", "from" => "process.inputs.company" } ] }
      expect(resolver.resolve(defn)).to eq({ "company" => "Acme" })
    end

    it "uses a default value when the reference is unresolved" do
      defn = { "inputs" => [ { "name" => "missing", "from" => "process.inputs.missing", "default" => "fallback" } ] }
      expect(resolver.resolve(defn)).to eq({ "missing" => "fallback" })
    end
  end

  describe "#resolve_reference" do
    it "resolves process.inputs.<name>" do
      expect(resolver.resolve_reference("process.inputs.company")).to eq("Acme")
    end

    it "raises UnresolvedReference when the input key is missing" do
      expect { resolver.resolve_reference("process.inputs.missing") }
        .to raise_error(described_class::UnresolvedReference, /process\.inputs\.missing/)
    end

    it "resolves a completed step's output" do
      step = create(:sop_step, instance: instance, step_id: "first", state: "completed",
                               outputs: { "score" => 0.91 })
      instance.reload
      expect(resolver.resolve_reference("steps.first.outputs.score")).to eq(0.91)
      _ = step
    end

    it "raises when the referenced step has not completed" do
      create(:sop_step, instance: instance, step_id: "first", state: "active",
                        outputs: {})
      instance.reload
      expect { resolver.resolve_reference("steps.first.outputs.score") }
        .to raise_error(described_class::UnresolvedReference, /not completed/)
    end

    it "raises when the output key is missing on a completed step" do
      create(:sop_step, instance: instance, step_id: "first", state: "completed", outputs: { "other" => 1 })
      instance.reload
      expect { resolver.resolve_reference("steps.first.outputs.score") }
        .to raise_error(described_class::UnresolvedReference, /steps\.first\.outputs\.score/)
    end

    it "raises for an unknown step id" do
      expect { resolver.resolve_reference("steps.nope.outputs.x") }
        .to raise_error(described_class::UnresolvedReference, /unknown step/)
    end

    it "resolves env.<NAME> from ENV" do
      stub_const("ENV", ENV.to_hash.merge("SOP_TEST_ENV" => "hello"))
      expect(resolver.resolve_reference("env.SOP_TEST_ENV")).to eq("hello")
    end

    it "raises when the env var is not set" do
      # Ensure the var is not present in the current ENV
      ENV.delete("SOP_MISSING_ENV_XYZ")
      expect { resolver.resolve_reference("env.SOP_MISSING_ENV_XYZ") }
        .to raise_error(described_class::UnresolvedReference, /env var/)
    end

    it "resolves instance.id" do
      expect(resolver.resolve_reference("instance.id")).to eq(instance.id)
    end

    it "resolves instance.started_at after start" do
      instance.update!(started_at: Time.current, state: "running")
      expect(resolver.resolve_reference("instance.started_at")).to be_within(2.seconds).of(Time.current)
    end

    it "resolves instance.<metadata_field>" do
      expect(resolver.resolve_reference("instance.deal_id")).to eq("XYZ-1")
    end

    it "raises on unrecognized reference syntax" do
      expect { resolver.resolve_reference("bogus.ref") }
        .to raise_error(described_class::UnresolvedReference, /unrecognized reference/)
    end
  end

  describe "#resolve_reference with collection selectors (SPEC v0.2 §2.7)" do
    let(:classifications) do
      [ { "label" => "spam", "score" => 0.9 }, { "label" => "ham", "score" => 0.1 } ]
    end

    before do
      create(:sop_step, instance: instance, step_id: "first", state: "completed",
                        outputs: { "classifications" => classifications, "score" => 0.42 })
      instance.reload
    end

    it "returns the whole array for a bare path" do
      expect(resolver.resolve_reference("steps.first.outputs.classifications"))
        .to eq(classifications)
    end

    it "returns the whole array for [*]" do
      expect(resolver.resolve_reference("steps.first.outputs.classifications[*]"))
        .to eq(classifications)
    end

    it "returns the indexed item for [<n>]" do
      expect(resolver.resolve_reference("steps.first.outputs.classifications[0]"))
        .to eq({ "label" => "spam", "score" => 0.9 })
    end

    it "returns nil for an out-of-range index" do
      expect(resolver.resolve_reference("steps.first.outputs.classifications[99]"))
        .to be_nil
    end

    it "plucks a string-valued field with [*].<field>" do
      expect(resolver.resolve_reference("steps.first.outputs.classifications[*].label"))
        .to eq([ "spam", "ham" ])
    end

    it "plucks a numeric-valued field with [*].<field>" do
      expect(resolver.resolve_reference("steps.first.outputs.classifications[*].score"))
        .to eq([ 0.9, 0.1 ])
    end

    it "drops items missing the plucked field (no nil placeholders)" do
      mixed = [ { "label" => "a" }, { "score" => 0.5 }, { "label" => "b" } ]
      create(:sop_step, instance: instance, step_id: "mixed", state: "completed",
                        outputs: { "items" => mixed })
      instance.reload
      expect(resolver.resolve_reference("steps.mixed.outputs.items[*].label"))
        .to eq([ "a", "b" ])
    end

    it "raises when an index selector is applied to a non-array value" do
      expect { resolver.resolve_reference("steps.first.outputs.score[0]") }
        .to raise_error(described_class::UnresolvedReference, /non-array/)
    end

    it "raises when [*] is applied to a non-array value" do
      expect { resolver.resolve_reference("steps.first.outputs.score[*]") }
        .to raise_error(described_class::UnresolvedReference, /non-array/)
    end

    it "raises a clear error for nested [*] selectors" do
      expect { resolver.resolve_reference("steps.first.outputs.classifications[*].label[*]") }
        .to raise_error(described_class::UnresolvedReference,
                        /nested \[\*\] selectors are not supported in v0\.2/)
    end

    it "raises for an unrecognized selector form" do
      expect { resolver.resolve_reference("steps.first.outputs.classifications[bogus]") }
        .to raise_error(described_class::UnresolvedReference, /unrecognized collection selector/)
    end
  end
end
