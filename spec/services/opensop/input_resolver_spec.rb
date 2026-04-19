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
end
