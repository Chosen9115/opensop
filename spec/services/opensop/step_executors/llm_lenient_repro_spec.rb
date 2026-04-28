require "rails_helper"

# Repro for HermesOS Issue #3 — `expected_output_schema:` reportedly silent-lenient.
#
# The Hermes report claims that when an llm step's response is missing a
# required schema key (or isn't even a JSON object at all), the runtime
# silently fills outputs with `null` and reports `state: completed` instead of
# failing the step. Inspection of `Opensop::StepExecutors::Llm` and
# `Opensop::OutputSchemaValidator` suggests the runtime IS strict — the
# validator raises `Invalid` on missing keys / non-object responses, and the
# executor re-raises `StepFailure` after exhausting retries.
#
# This spec pins the strict behavior so we either:
#   (a) confirm the report is from older code (these specs PASS on main), or
#   (b) catch a real bug if any path silently swallows validation errors.
RSpec.describe Opensop::StepExecutors::Llm, "schema-strictness repro" do
  let(:instance) { create(:sop_instance) }
  let(:step) do
    create(:sop_step,
           instance: instance,
           step_type: "llm",
           inputs: { "msg" => "hello" })
  end

  let(:schema) do
    {
      "intent"     => "enum[a, b, c]",
      "confidence" => "number"
    }
  end

  let(:base_definition) do
    {
      "model"                  => "claude-test",
      "prompt"                 => "Classify: {{ msg }}",
      "tools"                  => [],
      "expected_output_schema" => schema,
      "retry_on_incomplete"    => false,
      "max_retries"            => 0
    }
  end

  after { described_class.reset_provider_resolver! }

  def use_stub(canned_response)
    stub = Opensop::LlmProviders::TestStub.new(canned_response: canned_response)
    described_class.provider_resolver = ->(_model) { stub }
    stub
  end

  describe "missing required key (Hermes Issue #3 case A)" do
    it "raises StepFailure naming the missing field — does NOT silently complete" do
      use_stub({ "intent" => "a" }) # missing :confidence

      expect {
        described_class.new.call(step, instance, base_definition)
      }.to raise_error(described_class::StepFailure, /confidence.*missing/i)

      calls = step.llm_calls.reload
      expect(calls.size).to eq(1)
      expect(calls.first.status_schema_failed?).to be(true)
      expect(calls.first.error).to include("confidence")
      # Raw response should be persisted for debugging.
      expect(calls.first.response_payload["content"]).to eq("intent" => "a")
    end
  end

  describe "non-object response (Hermes Issue #3 case B)" do
    it "raises StepFailure when the provider returns a non-Hash content" do
      # Bypass parse_content_json by injecting a String directly via TestStub.
      use_stub("hello")

      expect {
        described_class.new.call(step, instance, base_definition)
      }.to raise_error(described_class::StepFailure, /expected object/)

      calls = step.llm_calls.reload
      expect(calls.size).to eq(1)
      expect(calls.first.status_schema_failed?).to be(true)
      expect(calls.first.error).to match(/expected object/)
    end
  end

  describe "wrong type for declared field" do
    it "raises StepFailure naming the field whose type didn't match" do
      use_stub({ "intent" => "a", "confidence" => "not-a-number" })

      expect {
        described_class.new.call(step, instance, base_definition)
      }.to raise_error(described_class::StepFailure, /confidence/)

      calls = step.llm_calls.reload
      expect(calls.first.status_schema_failed?).to be(true)
    end
  end

  describe "enum value mismatch" do
    it "raises StepFailure when an enum-declared field's value isn't in the list" do
      use_stub({ "intent" => "z", "confidence" => 0.9 })

      expect {
        described_class.new.call(step, instance, base_definition)
      }.to raise_error(described_class::StepFailure, /intent/)
    end
  end
end
