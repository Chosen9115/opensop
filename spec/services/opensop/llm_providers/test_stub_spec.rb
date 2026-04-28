# frozen_string_literal: true

require "rails_helper"

RSpec.describe Opensop::LlmProviders::TestStub do
  it "returns the canned response with stub metadata" do
    canned = { "decision" => "approve", "reason" => "looks fine" }
    stub = described_class.new(canned_response: canned)

    response = stub.call(prompt: "anything", expected_output_schema: { "decision" => "string" })

    expect(response).to be_a(Opensop::LlmProviders::Response)
    expect(response.content).to eq(canned)
    expect(response.raw_text).to eq(canned.to_json)
    expect(response.input_tokens).to eq(1)
    expect(response.output_tokens).to eq(1)
    expect(response.cost_cents).to be_nil
    expect(response.model).to eq("test-stub")
    expect(response.tool_calls).to eq([])
  end
end
