# frozen_string_literal: true

require "digest"

module Opensop
  module StepExecutors
    # Executes `llm` steps (SPEC-v0.2 §2.5).
    #
    # Pipeline per call:
    #   1. Render the prompt (inline or from file) with `{{ var }}` substitution
    #      using the step's resolved `inputs:` hash.
    #   2. Validate every declared tool name against `Opensop::ToolRegistry`.
    #   3. Pick a provider for the requested model.
    #   4. Loop up to `max_attempts`:
    #        - record an Sop::LlmCall row in `:requested`
    #        - call the provider
    #        - on CallFailed -> mark `:errored` and raise StepFailure
    #        - on success -> validate against `expected_output_schema`
    #            * invalid -> mark `:schema_failed`; retry if attempts remain,
    #              augmenting the prompt with a corrective preamble that names
    #              the prior validation errors
    #            * valid -> mark `:succeeded`, return `{ outputs: validated }`
    #
    # Provider resolution is exposed via `provider_resolver=` so specs can
    # swap in `Opensop::LlmProviders::TestStub` without monkey-patching.
    class Llm
      class StepFailure < StandardError; end

      DEFAULT_MAX_RETRIES = 2

      class << self
        # Tests inject a `->(model_string) { provider_instance }` callable.
        # Defaults to the built-in `provider_for` lookup.
        attr_writer :provider_resolver

        def provider_resolver
          @provider_resolver ||= ->(model) { default_provider_for(model) }
        end

        def reset_provider_resolver!
          @provider_resolver = nil
        end

        def default_provider_for(model)
          model_str = model.to_s
          if model_str.start_with?("claude")
            Opensop::LlmProviders::Anthropic.new(model: model_str)
          else
            raise StepFailure, "no provider configured for model '#{model_str}'"
          end
        end
      end

      def call(step, instance, definition)
        model = definition["model"]
        raise StepFailure, "llm step is missing `model:`" if model.blank?

        schema = definition["expected_output_schema"] || {}
        unless schema.is_a?(Hash)
          raise StepFailure, "llm step `expected_output_schema:` must be a Hash"
        end

        validator = Opensop::OutputSchemaValidator.new(schema)

        declared_tools = Array(definition["tools"])
        declared_tools.each do |tool_name|
          unless Opensop::ToolRegistry.allowed?(tool_name)
            raise StepFailure, "unknown tool '#{tool_name}'"
          end
        end

        rendered_prompt = render_prompt(definition, step)
        provider = self.class.provider_resolver.call(model)

        max_attempts = compute_max_attempts(definition)
        last_errors = nil

        (1..max_attempts).each do |attempt|
          Rails.logger.info(
            "[Opensop::StepExecutors::Llm] step=#{step.step_id} model=#{model} attempt=#{attempt}"
          )

          attempt_prompt =
            if attempt == 1 || last_errors.nil?
              rendered_prompt
            else
              corrective_preamble(last_errors) + "\n\n" + rendered_prompt
            end

          prompt_hash = Digest::SHA256.hexdigest(attempt_prompt)
          llm_call = step.llm_calls.create!(
            status: :requested,
            attempt: attempt,
            model: model,
            prompt_hash: prompt_hash,
            started_at: Time.current,
            request_payload: {
              "model" => model,
              "prompt" => attempt_prompt,
              "tools" => declared_tools,
              "expected_output_schema" => schema,
              "attempt" => attempt
            }
          )

          response =
            begin
              provider.call(
                prompt: attempt_prompt,
                tools: declared_tools,
                expected_output_schema: schema
              )
            rescue Opensop::LlmProviders::CallFailed => e
              llm_call.update!(
                status: :errored,
                error: e.message,
                finished_at: Time.current
              )
              raise StepFailure, "llm call failed: #{e.message}"
            end

          response_payload = build_response_payload(response)

          begin
            validated = validator.validate!(response.content)
          rescue Opensop::OutputSchemaValidator::Invalid => e
            last_errors = e.errors
            llm_call.update!(
              status: :schema_failed,
              error: e.errors.join("; "),
              response_payload: response_payload,
              input_tokens: response.input_tokens,
              output_tokens: response.output_tokens,
              cost_cents: response.cost_cents,
              finished_at: Time.current
            )

            if attempt < max_attempts
              next
            else
              raise StepFailure,
                    "llm output failed schema validation after #{attempt} attempts: " \
                    "#{e.errors.join('; ')}"
            end
          end

          llm_call.update!(
            status: :succeeded,
            response_payload: response_payload,
            input_tokens: response.input_tokens,
            output_tokens: response.output_tokens,
            cost_cents: response.cost_cents,
            finished_at: Time.current
          )

          return { outputs: validated }
        end

        # Unreachable — the loop either returns or raises — but keeps the
        # method's static return shape obvious.
        raise StepFailure, "llm executor exited retry loop without resolving"
      end

      private

      def compute_max_attempts(definition)
        retry_on_incomplete = definition.fetch("retry_on_incomplete", true)
        return 1 unless retry_on_incomplete

        max_retries = definition.fetch("max_retries", DEFAULT_MAX_RETRIES).to_i
        max_retries = 0 if max_retries.negative?
        max_retries + 1
      end

      def render_prompt(definition, step)
        body = load_prompt_body(definition)
        substitute_vars(body, step.inputs || {})
      end

      def load_prompt_body(definition)
        if definition["prompt_file"].present?
          path = Rails.root.join("processes", definition["prompt_file"]).to_s
          unless File.exist?(path)
            raise StepFailure, "prompt_file not found at #{path}"
          end
          File.read(path)
        elsif definition["prompt"].is_a?(String)
          definition["prompt"]
        else
          raise StepFailure, "llm step requires `prompt:` or `prompt_file:`"
        end
      end

      def substitute_vars(template, inputs)
        stringified = inputs.each_with_object({}) { |(k, v), h| h[k.to_s] = v }
        template.gsub(/\{\{\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\}\}/) do
          var = Regexp.last_match(1)
          if stringified.key?(var)
            stringified[var].to_s
          else
            Rails.logger.warn(
              "[Opensop::StepExecutors::Llm] missing template variable '#{var}'"
            )
            Regexp.last_match(0)
          end
        end
      end

      def corrective_preamble(errors)
        msg = Array(errors).join("; ")
        <<~SYS.strip
          Previous attempt failed validation: #{msg}.
          Return JSON only matching the schema.
        SYS
      end

      def build_response_payload(response)
        {
          "raw_text" => response.raw_text,
          "content" => response.content,
          "tokens" => {
            "input" => response.input_tokens,
            "output" => response.output_tokens
          }
        }
      end
    end
  end
end
