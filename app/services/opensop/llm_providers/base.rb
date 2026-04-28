# frozen_string_literal: true

module Opensop
  module LlmProviders
    # Standardized response returned by every LLM provider.
    #
    # Fields:
    #   content                — Hash, parsed JSON the model produced
    #   raw_text               — String, the model's raw text output
    #   input_tokens           — Integer, prompt tokens consumed
    #   output_tokens          — Integer, completion tokens consumed
    #   cost_cents             — Integer or nil, total cost in cents (nil if unknown)
    #   model                  — String, exact model id used
    #   tool_calls             — Array, reserved for future tool-use support (empty in v0.2)
    Response = Struct.new(
      :content,
      :raw_text,
      :input_tokens,
      :output_tokens,
      :cost_cents,
      :model,
      :tool_calls,
      keyword_init: true
    )

    # Raised when the provider call fails for any reason (HTTP error, parse error,
    # auth failure, etc). Wraps the underlying error so callers see a single, clear
    # exception type.
    class CallFailed < StandardError; end

    # Abstract base class for LLM providers. Concrete subclasses (e.g. Anthropic,
    # TestStub) must implement #call.
    class Base
      # @param prompt [String] the user prompt to send the model
      # @param tools [Array] reserved for future tool-use support (ignored in v0.2)
      # @param expected_output_schema [Hash, nil] JSON-schema-style hash describing the
      #   expected shape of the model's output. Providers should pass this to the model
      #   so it knows what JSON to produce.
      # @param temperature [Float, nil] sampling temperature; nil leaves provider default
      # @param max_tokens [Integer, nil] max output tokens; nil leaves provider default
      # @return [Opensop::LlmProviders::Response]
      def call(prompt:, tools: [], expected_output_schema: nil, temperature: nil, max_tokens: nil)
        raise NotImplementedError, "#{self.class} must implement #call"
      end
    end
  end
end
