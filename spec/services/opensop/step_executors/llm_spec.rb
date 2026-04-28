require "rails_helper"

RSpec.describe Opensop::StepExecutors::Llm do
  let(:instance) { create(:sop_instance) }
  let(:step) do
    create(:sop_step,
           instance: instance,
           step_type: "automated",
           inputs: { "name" => "Ada", "topic" => "logic" })
  end

  let(:schema) do
    {
      "summary"    => "string",
      "confidence" => "number"
    }
  end

  let(:base_definition) do
    {
      "model"                   => "claude-test",
      "prompt"                  => "Hello {{ name }} about {{ topic }}.",
      "tools"                   => [],
      "expected_output_schema"  => schema,
      "retry_on_incomplete"     => true,
      "max_retries"             => 2
    }
  end

  after do
    described_class.reset_provider_resolver!
  end

  # Builds a single provider instance whose internal queue rotates per call —
  # mirrors how a real provider behaves across retries (one instance, many calls).
  def use_stub(*responses)
    queue = responses.dup
    queue_provider = Class.new(Opensop::LlmProviders::Base) do
      def initialize(queue)
        super()
        @queue = queue
      end

      def call(prompt:, tools: [], expected_output_schema: nil, temperature: nil, max_tokens: nil)
        canned = @queue.shift
        raise "stub queue exhausted" if canned.nil?
        Opensop::LlmProviders::TestStub.new(canned_response: canned).call(
          prompt: prompt,
          tools: tools,
          expected_output_schema: expected_output_schema,
          temperature: temperature,
          max_tokens: max_tokens
        )
      end
    end.new(queue)

    described_class.provider_resolver = ->(_model) { queue_provider }
    queue_provider
  end

  def use_provider(provider)
    described_class.provider_resolver = ->(_model) { provider }
  end

  describe "#call — happy path" do
    it "returns validated outputs and records one succeeded LlmCall" do
      use_stub({ "summary" => "ok", "confidence" => 0.91 })

      result = described_class.new.call(step, instance, base_definition)

      expect(result).to eq(outputs: { "summary" => "ok", "confidence" => 0.91 })

      calls = step.llm_calls.reload
      expect(calls.size).to eq(1)
      call = calls.first
      expect(call.status_succeeded?).to be(true)
      expect(call.attempt).to eq(1)
      expect(call.model).to eq("claude-test")
      expect(call.input_tokens).to eq(1)
      expect(call.output_tokens).to eq(1)
      expect(call.prompt_hash).to eq(Digest::SHA256.hexdigest("Hello Ada about logic."))
      expect(call.started_at).to be_present
      expect(call.finished_at).to be_present
      expect(call.response_payload["content"]).to eq({ "summary" => "ok", "confidence" => 0.91 })
      expect(call.response_payload["tokens"]).to eq({ "input" => 1, "output" => 1 })
    end
  end

  describe "#call — retry on schema failure then succeed" do
    it "creates one schema_failed row and one succeeded row" do
      # First response is missing :confidence (schema fail);
      # second response is valid.
      use_stub(
        { "summary" => "first" },
        { "summary" => "second", "confidence" => 0.5 }
      )

      result = described_class.new.call(step, instance, base_definition)

      expect(result[:outputs]).to eq("summary" => "second", "confidence" => 0.5)

      calls = step.llm_calls.reload.order(:attempt)
      expect(calls.size).to eq(2)
      expect(calls.first.status_schema_failed?).to be(true)
      expect(calls.first.attempt).to eq(1)
      expect(calls.first.error).to include("confidence")
      expect(calls.last.status_succeeded?).to be(true)
      expect(calls.last.attempt).to eq(2)
      # Second attempt prompt was augmented with corrective preamble,
      # so its prompt_hash differs from attempt 1.
      expect(calls.last.prompt_hash).not_to eq(calls.first.prompt_hash)
    end
  end

  describe "#call — schema failure exhausts retries" do
    it "raises StepFailure and writes max_attempts schema_failed rows" do
      # max_retries: 2 => max_attempts == 3
      use_stub(
        { "summary" => "a" },
        { "summary" => "b" },
        { "summary" => "c" }
      )

      expect {
        described_class.new.call(step, instance, base_definition)
      }.to raise_error(described_class::StepFailure, /failed schema validation after 3 attempts/)

      calls = step.llm_calls.reload
      expect(calls.size).to eq(3)
      expect(calls.map(&:status).uniq).to eq(["schema_failed"])
    end

    it "respects retry_on_incomplete: false (single attempt)" do
      use_stub({ "summary" => "x" })

      defn = base_definition.merge("retry_on_incomplete" => false)

      expect {
        described_class.new.call(step, instance, defn)
      }.to raise_error(described_class::StepFailure, /after 1 attempts/)

      expect(step.llm_calls.reload.size).to eq(1)
    end
  end

  describe "#call — provider raises CallFailed" do
    it "marks the LlmCall errored and raises StepFailure" do
      failing = Class.new(Opensop::LlmProviders::Base) do
        def call(prompt:, tools: [], expected_output_schema: nil, temperature: nil, max_tokens: nil)
          raise Opensop::LlmProviders::CallFailed, "boom"
        end
      end.new
      use_provider(failing)

      expect {
        described_class.new.call(step, instance, base_definition)
      }.to raise_error(described_class::StepFailure, /llm call failed: boom/)

      calls = step.llm_calls.reload
      expect(calls.size).to eq(1)
      expect(calls.first.status_errored?).to be(true)
      expect(calls.first.error).to eq("boom")
      expect(calls.first.finished_at).to be_present
    end
  end

  describe "#call — tool validation" do
    it "raises StepFailure for an unknown tool before any provider call" do
      provider_invoked = false
      described_class.provider_resolver = lambda do |_model|
        provider_invoked = true
        Opensop::LlmProviders::TestStub.new(canned_response: {})
      end

      defn = base_definition.merge("tools" => ["NotARealTool"])

      expect {
        described_class.new.call(step, instance, defn)
      }.to raise_error(described_class::StepFailure, /unknown tool 'NotARealTool'/)

      expect(provider_invoked).to be(false)
      expect(step.llm_calls.reload.size).to eq(0)
    end

    it "accepts built-in tool names (Read, Grep)" do
      use_stub({ "summary" => "ok", "confidence" => 0.7 })

      defn = base_definition.merge("tools" => ["Read", "Grep"])

      result = described_class.new.call(step, instance, defn)
      expect(result[:outputs]["summary"]).to eq("ok")

      call = step.llm_calls.reload.first
      expect(call.request_payload["tools"]).to eq(["Read", "Grep"])
    end
  end

  describe "#call — provider resolution" do
    it "raises StepFailure for an unknown model prefix" do
      # Reset to default lookup so we exercise the real provider_for.
      described_class.reset_provider_resolver!

      defn = base_definition.merge("model" => "gpt-4o")

      expect {
        described_class.new.call(step, instance, defn)
      }.to raise_error(described_class::StepFailure, /no provider configured for model 'gpt-4o'/)
    end
  end

  describe "#call — prompt_file" do
    it "loads the prompt from the configured file under processes/" do
      rel = "tmp-prompts/llm-spec-#{SecureRandom.hex(4)}.md"
      absolute = Rails.root.join("processes", rel).to_s
      FileUtils.mkdir_p(File.dirname(absolute))
      File.write(absolute, "From file: {{ name }}.")

      capture_provider = Class.new(Opensop::LlmProviders::Base) do
        attr_reader :seen
        def call(prompt:, tools: [], expected_output_schema: nil, temperature: nil, max_tokens: nil)
          @seen = prompt
          Opensop::LlmProviders::Response.new(
            content: { "summary" => "ok", "confidence" => 0.9 },
            raw_text: "{}",
            input_tokens: 0, output_tokens: 0, cost_cents: nil,
            model: "test", tool_calls: []
          )
        end
      end.new
      described_class.provider_resolver = ->(_model) { capture_provider }

      defn = base_definition.except("prompt").merge("prompt_file" => rel)

      described_class.new.call(step, instance, defn)
      expect(capture_provider.seen).to eq("From file: Ada.")
    ensure
      FileUtils.rm_f(absolute) if absolute
    end

    it "raises StepFailure when prompt_file is missing" do
      defn = base_definition.except("prompt").merge("prompt_file" => "nope/missing-#{SecureRandom.hex(4)}.md")

      expect {
        described_class.new.call(step, instance, defn)
      }.to raise_error(described_class::StepFailure, /prompt_file not found/)
    end
  end

  describe "#call — variable substitution" do
    it "substitutes declared input variables" do
      capture = Class.new(Opensop::LlmProviders::Base) do
        attr_reader :seen
        def call(prompt:, tools: [], expected_output_schema: nil, temperature: nil, max_tokens: nil)
          @seen = prompt
          Opensop::LlmProviders::Response.new(
            content: { "summary" => "ok", "confidence" => 1 },
            raw_text: "{}",
            input_tokens: 0, output_tokens: 0, cost_cents: nil,
            model: "test", tool_calls: []
          )
        end
      end.new
      use_provider(capture)

      described_class.new.call(step, instance, base_definition)

      expect(capture.seen).to eq("Hello Ada about logic.")
    end

    it "leaves unknown variables untouched and warns" do
      capture = Class.new(Opensop::LlmProviders::Base) do
        attr_reader :seen
        def call(prompt:, tools: [], expected_output_schema: nil, temperature: nil, max_tokens: nil)
          @seen = prompt
          Opensop::LlmProviders::Response.new(
            content: { "summary" => "ok", "confidence" => 1 },
            raw_text: "{}",
            input_tokens: 0, output_tokens: 0, cost_cents: nil,
            model: "test", tool_calls: []
          )
        end
      end.new
      use_provider(capture)

      defn = base_definition.merge("prompt" => "Hi {{ name }}, missing {{ unknown_var }}!")
      expect(Rails.logger).to receive(:warn).with(/missing template variable 'unknown_var'/).at_least(:once)
      allow(Rails.logger).to receive(:info)

      described_class.new.call(step, instance, defn)

      expect(capture.seen).to eq("Hi Ada, missing {{ unknown_var }}!")
    end
  end
end
