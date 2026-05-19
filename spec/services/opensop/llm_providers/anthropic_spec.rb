# frozen_string_literal: true

require "rails_helper"

RSpec.describe Opensop::LlmProviders::Anthropic do
  let(:api_key) { "sk-ant-test-key" }
  let(:model)   { "claude-sonnet-4-7" }
  let(:provider) { described_class.new(api_key: api_key, model: model) }
  let(:endpoint) { "https://api.anthropic.com/v1/messages" }

  let(:expected_schema) do
    { "decision" => "string", "confidence" => "number" }
  end

  def stub_anthropic(status:, body:)
    stub_request(:post, endpoint).to_return(
      status: status,
      body: body.is_a?(String) ? body : body.to_json,
      headers: { "Content-Type" => "application/json" }
    )
  end

  describe "#call" do
    context "happy path" do
      let(:json_text) { { "decision" => "approve", "confidence" => 0.91 }.to_json }
      let(:api_body) do
        {
          "id" => "msg_01ABC",
          "type" => "message",
          "role" => "assistant",
          "model" => "claude-sonnet-4-7",
          "content" => [ { "type" => "text", "text" => json_text } ],
          "stop_reason" => "end_turn",
          "usage" => { "input_tokens" => 42, "output_tokens" => 17 }
        }
      end

      before { stub_anthropic(status: 200, body: api_body) }

      it "parses JSON content, populates tokens, and exposes the model id" do
        response = provider.call(
          prompt: "Should we approve this refund?",
          expected_output_schema: expected_schema
        )

        expect(response).to be_a(Opensop::LlmProviders::Response)
        expect(response.content).to eq("decision" => "approve", "confidence" => 0.91)
        expect(response.raw_text).to eq(json_text)
        expect(response.input_tokens).to eq(42)
        expect(response.output_tokens).to eq(17)
        expect(response.model).to eq("claude-sonnet-4-7")
        expect(response.cost_cents).to be_nil
        expect(response.tool_calls).to eq([])
      end

      it "sends the expected headers and body to the Anthropic API" do
        provider.call(
          prompt: "Hello",
          expected_output_schema: expected_schema,
          temperature: 0.2,
          max_tokens: 1024
        )

        expect(WebMock).to have_requested(:post, endpoint).with { |req|
          req.headers["X-Api-Key"] == api_key &&
            req.headers["Anthropic-Version"] == "2023-06-01" &&
            (parsed = JSON.parse(req.body)) &&
            parsed["model"] == model &&
            parsed["max_tokens"] == 1024 &&
            parsed["temperature"] == 0.2 &&
            parsed["messages"].is_a?(Array) &&
            parsed["messages"].first["role"] == "user" &&
            parsed["messages"].first["content"] == "Hello" &&
            parsed["system"].is_a?(String) &&
            parsed["system"].include?("JSON") &&
            parsed["system"].include?("decision")
        }
      end
    end

    context "when the response text is wrapped in a code fence" do
      let(:fenced_text) { "```json\n{\"decision\":\"reject\"}\n```" }
      let(:api_body) do
        {
          "model" => "claude-sonnet-4-7",
          "content" => [ { "type" => "text", "text" => fenced_text } ],
          "usage" => { "input_tokens" => 5, "output_tokens" => 6 }
        }
      end

      before { stub_anthropic(status: 200, body: api_body) }

      it "strips the code fence and parses the inner JSON" do
        response = provider.call(prompt: "ok", expected_output_schema: expected_schema)
        expect(response.content).to eq("decision" => "reject")
        expect(response.raw_text).to eq(fenced_text)
      end
    end

    context "when the API returns 401" do
      before do
        stub_anthropic(
          status: 401,
          body: { "error" => { "type" => "authentication_error", "message" => "invalid x-api-key" } }
        )
      end

      it "raises CallFailed with a useful message" do
        expect {
          provider.call(prompt: "hi", expected_output_schema: expected_schema)
        }.to raise_error(Opensop::LlmProviders::CallFailed, /HTTP 401/)
      end
    end

    context "when the model returns malformed JSON text" do
      let(:api_body) do
        {
          "model" => "claude-sonnet-4-7",
          "content" => [ { "type" => "text", "text" => "this is not json at all" } ],
          "usage" => { "input_tokens" => 1, "output_tokens" => 1 }
        }
      end

      before { stub_anthropic(status: 200, body: api_body) }

      it "raises CallFailed mentioning the parse failure" do
        expect {
          provider.call(prompt: "hi", expected_output_schema: expected_schema)
        }.to raise_error(Opensop::LlmProviders::CallFailed, /not valid JSON/)
      end
    end

    context "when no API key is configured" do
      let(:provider) { described_class.new(api_key: nil) }

      it "raises CallFailed before issuing any request" do
        expect {
          provider.call(prompt: "hi")
        }.to raise_error(Opensop::LlmProviders::CallFailed, /ANTHROPIC_API_KEY/)
        expect(WebMock).not_to have_requested(:post, endpoint)
      end
    end
  end
end
