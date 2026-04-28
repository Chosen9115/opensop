# frozen_string_literal: true

require "json"

module Opensop
  module LlmProviders
    # Test-only LLM provider that returns a canned response. Lets specs and
    # end-to-end tests drive `llm` step execution without hitting the network.
    #
    # Example:
    #   stub = Opensop::LlmProviders::TestStub.new(canned_response: { "decision" => "approve" })
    #   stub.call(prompt: "anything").content # => { "decision" => "approve" }
    class TestStub < Base
      def initialize(canned_response:)
        super()
        @canned_response = canned_response
      end

      def call(prompt:, tools: [], expected_output_schema: nil, temperature: nil, max_tokens: nil)
        Response.new(
          content: @canned_response,
          raw_text: @canned_response.to_json,
          input_tokens: 1,
          output_tokens: 1,
          cost_cents: nil,
          model: "test-stub",
          tool_calls: []
        )
      end
    end
  end
end
