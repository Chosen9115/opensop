require 'rails_helper'

RSpec.describe Opensop::ConditionEvaluator do
  let(:process) do
    build_process(
      name: "cond-proc",
      steps: [ { "id" => "a", "name" => "A", "type" => "notification" } ]
    )
  end
  let(:instance) do
    create(:sop_instance,
           process: process,
           inputs: { "x" => "yes" })
  end
  let(:evaluator) { described_class.new(instance: instance) }

  describe "#call" do
    context "with blank input" do
      it "returns true for nil" do
        expect(evaluator.call(nil)).to be true
      end

      it "returns true for an empty string" do
        expect(evaluator.call("")).to be true
      end
    end

    context "literals and operators" do
      it "supports equality on process inputs" do
        expect(evaluator.call("process.inputs.x == 'yes'")).to be true
        expect(evaluator.call("process.inputs.x == 'no'")).to be false
      end

      it "supports inequality" do
        expect(evaluator.call("process.inputs.x != 'no'")).to be true
        expect(evaluator.call("process.inputs.x != 'yes'")).to be false
      end

      it "supports numeric comparison on step outputs" do
        create(:sop_step, instance: instance, step_id: "a", state: "completed",
                          outputs: { "score" => 0.92 })
        instance.reload

        expect(evaluator.call("steps.a.outputs.score >= 0.8")).to be true
        expect(evaluator.call("steps.a.outputs.score < 0.5")).to be false
      end

      it "supports string != on step outputs" do
        create(:sop_step, instance: instance, step_id: "a", state: "completed",
                          outputs: { "result" => "ok" })
        instance.reload

        expect(evaluator.call("steps.a.outputs.result != 'invalid'")).to be true
      end

      it "supports && and ||" do
        expect(evaluator.call("process.inputs.x == 'yes' && 1 < 2")).to be true
        expect(evaluator.call("process.inputs.x == 'no'  || 1 < 2")).to be true
        expect(evaluator.call("process.inputs.x == 'no'  && 1 < 2")).to be false
      end

      it "supports ! (not)" do
        expect(evaluator.call("!(process.inputs.x == 'no')")).to be true
      end

      it "supports parenthesization" do
        expect(evaluator.call("(1 == 1) || (2 == 3)")).to be true
        expect(evaluator.call("(1 == 2) || (2 == 3)")).to be false
      end
    end

    context "unresolved references" do
      it "evaluates comparisons with unresolved refs to false (does not raise)" do
        expect(evaluator.call("process.inputs.missing == 'anything'")).to be false
      end
    end

    context "malicious / invalid input" do
      it "rejects Ruby method calls via InvalidExpression" do
        expect { evaluator.call("system('rm -rf /')") }
          .to raise_error(described_class::InvalidExpression)
      end

      it "rejects trailing garbage" do
        expect { evaluator.call("1 == 1 foo") }
          .to raise_error(described_class::InvalidExpression)
      end
    end
  end
end
