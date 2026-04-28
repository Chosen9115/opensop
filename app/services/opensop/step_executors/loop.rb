# frozen_string_literal: true

require "json"

module Opensop
  module StepExecutors
    # Executes `loop` steps (SPEC-v0.2 §2.9).
    #
    # Three variants, distinguished by which key appears under `loop:`:
    #   * `for_each: <ref>`  iterate over a resolved collection
    #   * `repeat_until: <expr>`  iterate until predicate true (post-check)
    #   * `while: <expr>`  iterate while predicate true (pre-check)
    #
    # Per iteration:
    #   1. Create an Sop::StepIteration row with iteration_inputs binding the
    #      iteration variable (`as:` -> value) and `index`.
    #   2. For each body step definition (in order):
    #        - resolve the body step's inputs (supporting `loop.<as>` and
    #          `loop.index` references against iteration_inputs)
    #        - persist a real Sop::Step row tied to the iteration via
    #          parent_iteration_id, with a synthetic step_id of
    #          "<parent_step_id>/<i>/<body_id>"
    #        - dispatch to the appropriate executor
    #        - on success: mark body step completed and capture its outputs
    #        - on failure: mark both the body step and iteration as failed,
    #          then re-raise as StepFailure (no partial-iteration aggregation)
    #   3. Compose iteration outputs as { body_step_id => body_outputs } and
    #      mark the iteration completed.
    #
    # After the loop terminates, aggregate per declared loop output:
    #   * `aggregate:` rule of `concat | sum | last`
    #   * if no rule given for an output, default to `last`.
    #
    # The whole loop executes synchronously inside one `#call`.
    class Loop
      class StepFailure < StandardError; end

      # Mirrors DefinitionParser::LOOP_MAX_ITERATIONS_TEMPLATE_FORMAT — kept
      # local so this executor doesn't depend on the parser at runtime.
      MAX_ITERATIONS_TEMPLATE_FORMAT = /\A\{\{\s*process\.inputs\.([A-Za-z_][A-Za-z0-9_]*)\s*\}\}\z/

      def call(step, instance, definition)
        loop_block = definition["loop"] || {}
        body_defs  = Array(definition["body"])
        outputs_decl = Array(definition["outputs"])
        aggregate_rules = loop_block["aggregate"].is_a?(Hash) ? loop_block["aggregate"] : {}
        as_name        = loop_block["as"] || "item"
        max_iterations = resolve_max_iterations(loop_block["max_iterations"], instance)
        max_iterations = 1000 if max_iterations <= 0

        variant, variant_value = detect_variant(loop_block)

        collection = nil
        if variant == "for_each"
          collection = resolve_collection(variant_value, instance)
        end

        iteration_records = []
        i = 0

        Rails.logger.info(
          "[Opensop::StepExecutors::Loop] step=#{step.step_id} variant=#{variant} max=#{max_iterations}"
        )

        loop do
          if i >= max_iterations
            case variant
            when "for_each"
              # Defensive: collection length should naturally bound this.
              Rails.logger.warn(
                "[Opensop::StepExecutors::Loop] step=#{step.step_id} hit max_iterations=#{max_iterations} during for_each — terminating"
              )
              break
            else
              raise StepFailure, "loop hit max_iterations (#{max_iterations})"
            end
          end

          # Termination check for `for_each` (collection exhausted) and
          # pre-check for `while:`.
          case variant
          when "for_each"
            break if i >= collection.length
          when "while"
            break unless evaluate_predicate(variant_value, instance, iteration_records.last)
          end

          iter_value =
            case variant
            when "for_each" then collection[i]
            else nil
            end

          iteration = Sop::StepIteration.create!(
            parent_step: step,
            index: i,
            state: :running,
            started_at: Time.current,
            iteration_inputs: { as_name => iter_value, "index" => i }
          )

          begin
            body_outputs_by_id = run_body!(body_defs, instance, step, iteration, i)
          rescue StandardError => e
            iteration.update!(
              state: :failed,
              error: e.message,
              finished_at: Time.current
            )
            raise StepFailure, e.message if e.is_a?(StepFailure)
            raise StepFailure, e.message
          end

          iteration.update!(
            state: :completed,
            outputs: body_outputs_by_id,
            finished_at: Time.current
          )
          iteration_records << iteration

          # Post-check for `repeat_until:`.
          # Predicate context: `outputs.<key>` resolves to the LAST body
          # step's outputs in the latest iteration. This is the v0.2
          # convention — the last body step is the natural "result" of the
          # iteration and avoids ambiguity when multiple body steps exist.
          if variant == "repeat_until"
            break if evaluate_predicate(variant_value, instance, iteration)
          end

          i += 1
        end

        aggregated = aggregate_outputs(outputs_decl, aggregate_rules, iteration_records, body_defs)
        { outputs: aggregated }
      end

      private

      # Resolves `max_iterations:` which may be either a literal positive
      # Integer or a `{{ process.inputs.<name> }}` template string. The parser
      # already enforces shape; here we resolve and type-check the resolved
      # value at instance-start time.
      def resolve_max_iterations(raw, instance)
        return raw.to_i if raw.is_a?(Integer)
        return raw.to_i unless raw.is_a?(String)

        m = raw.match(MAX_ITERATIONS_TEMPLATE_FORMAT)
        # If the parser let it through as a String it must match this pattern,
        # but be defensive in case this executor is invoked directly.
        unless m
          raise StepFailure,
                "loop max_iterations template #{raw.inspect} is malformed (expected `{{ process.inputs.<name> }}`)"
        end

        input_name = m[1]
        inputs = instance.inputs || {}
        unless inputs.key?(input_name) || inputs.key?(input_name.to_sym)
          raise StepFailure,
                "loop max_iterations references missing process input #{input_name.inspect}"
        end

        value = inputs[input_name] || inputs[input_name.to_sym]
        # Accept Integer or numeric String that parses cleanly to a positive int.
        coerced =
          case value
          when Integer then value
          when String
            if value.match?(/\A\d+\z/)
              value.to_i
            else
              raise StepFailure,
                    "loop max_iterations input #{input_name.inspect} must resolve to a positive integer (got #{value.inspect})"
            end
          else
            raise StepFailure,
                  "loop max_iterations input #{input_name.inspect} must resolve to a positive integer (got #{value.class})"
          end

        unless coerced > 0
          raise StepFailure,
                "loop max_iterations input #{input_name.inspect} must resolve to a positive integer (got #{coerced})"
        end
        coerced
      end

      def detect_variant(loop_block)
        %w[for_each repeat_until while].each do |key|
          return [key, loop_block[key]] if loop_block.key?(key)
        end
        # Parser already enforces this — defensive only.
        raise StepFailure, "loop step missing for_each / repeat_until / while"
      end

      def resolve_collection(reference, instance)
        resolver = Opensop::InputResolver.new(instance: instance)
        value =
          begin
            resolver.resolve_reference(reference.to_s)
          rescue Opensop::InputResolver::UnresolvedReference => e
            raise StepFailure, "loop for_each could not resolve #{reference.inspect}: #{e.message}"
          end

        unless value.is_a?(Array)
          raise StepFailure, "loop for_each did not resolve to an array (got #{value.class})"
        end
        value
      end

      # Evaluate a predicate string for `repeat_until:` / `while:`.
      #
      # Predicate convention: `outputs.<key>` refers to a key on the LAST body
      # step's outputs in the latest iteration. We preprocess the expression,
      # substituting each `outputs.<key>` reference with its literal value
      # (number / string / boolean / null) before handing the string to
      # ConditionEvaluator. This keeps the evaluator generic — it doesn't
      # need to know about iteration scope — at the cost of a tiny inline
      # substitution pass here.
      #
      # We also pass `extra: { "outputs" => last_outputs }` for parity with
      # the spec text, even though the dotted form is what the substitution
      # actually resolves.
      def evaluate_predicate(expression, instance, latest_iteration)
        last_outputs =
          if latest_iteration && latest_iteration.outputs.is_a?(Hash) && !latest_iteration.outputs.empty?
            latest_iteration.outputs.values.last || {}
          else
            {}
          end

        rewritten = rewrite_outputs_refs(expression.to_s, last_outputs)

        evaluator = Opensop::ConditionEvaluator.new(
          instance: instance,
          extra: { "outputs" => last_outputs }
        )
        !!evaluator.call(rewritten)
      rescue Opensop::ConditionEvaluator::InvalidExpression => e
        raise StepFailure, "invalid loop predicate #{expression.inspect}: #{e.message}"
      end

      # Inline-substitute `outputs.<key>` tokens with their literal value from
      # `last_outputs`. Unknown keys become `null`. Booleans/numbers/nil are
      # rendered as themselves; strings are JSON-quoted.
      def rewrite_outputs_refs(expression, last_outputs)
        expression.gsub(/\boutputs\.([a-zA-Z_][a-zA-Z0-9_]*)\b/) do
          key = Regexp.last_match(1)
          value =
            if last_outputs.key?(key)
              last_outputs[key]
            elsif last_outputs.key?(key.to_sym)
              last_outputs[key.to_sym]
            else
              nil
            end
          literalize(value)
        end
      end

      def literalize(value)
        case value
        when nil          then "null"
        when true, false  then value.to_s
        when Numeric      then value.to_s
        when String       then value.to_json
        else value.to_json
        end
      end

      def run_body!(body_defs, instance, parent_step, iteration, iteration_index)
        outputs_by_id = {}

        body_defs.each do |body_def|
          body_id = body_def["id"]
          synthetic_step_id = "#{parent_step.step_id}/#{iteration_index}/#{body_id}"

          resolved_inputs = resolve_body_inputs(body_def, instance, iteration)

          body_step = Sop::Step.create!(
            instance: instance,
            step_id: synthetic_step_id,
            step_name: body_def["name"] || body_id,
            step_type: body_def["type"],
            parent_iteration_id: iteration.id,
            # Body steps follow Sop::Step's enum (pending/active/completed/...)
            # — only the iteration row uses the StepIteration enum (running/...).
            state: :active,
            sub_state: "running",
            inputs: resolved_inputs,
            outputs: {},
            position: next_position_for(instance),
            attempt: 1,
            started_at: Time.current
          )

          begin
            executor = Opensop::StepExecutor.for(body_def["type"]).new
            result = executor.call(body_step, instance, body_def)
            body_outputs = (result && result[:outputs]) || {}
            body_step.update!(
              state: :completed,
              outputs: body_outputs,
              completed_at: Time.current
            )
            outputs_by_id[body_id] = body_outputs
          rescue StandardError => e
            body_step.update!(
              state: :failed,
              error: e.message,
              completed_at: Time.current
            )
            raise StepFailure,
                  "iteration #{iteration_index} failed at body step '#{body_id}': #{e.message}"
          end
        end

        outputs_by_id
      end

      # Resolve a body step's inputs.
      #
      # We can't hand the body step definition to InputResolver wholesale
      # because the resolver doesn't know about `loop.<as>` references —
      # those bind to the per-iteration `iteration_inputs` hash, not to the
      # instance. So we walk inputs manually: any `from:` starting with
      # `loop.` is satisfied from `iteration.iteration_inputs`; everything
      # else delegates to InputResolver, which handles process.inputs.*,
      # steps.*.outputs.*, etc.
      def resolve_body_inputs(body_def, instance, iteration)
        inputs = Array(body_def["inputs"])
        resolver = Opensop::InputResolver.new(instance: instance)
        iter_inputs = iteration.iteration_inputs || {}

        inputs.each_with_object({}) do |field, acc|
          name = field["name"]
          next unless name

          if field.key?("from") && field["from"].to_s.start_with?("loop.")
            ref_key = field["from"].to_s.sub(/\Aloop\./, "")
            value =
              if iter_inputs.key?(ref_key)
                iter_inputs[ref_key]
              elsif iter_inputs.key?(ref_key.to_sym)
                iter_inputs[ref_key.to_sym]
              elsif field.key?("default")
                field["default"]
              else
                raise StepFailure, "loop reference loop.#{ref_key} is not bound"
              end
            acc[name] = value
          else
            # Build a single-field schema slice and ask the resolver.
            single = { "inputs" => [field] }
            begin
              resolved = resolver.resolve(single)
              acc[name] = resolved[name]
            rescue Opensop::InputResolver::UnresolvedReference => e
              raise StepFailure, "could not resolve body input #{name.inspect}: #{e.message}"
            end
          end
        end
      end

      def next_position_for(instance)
        (instance.steps.maximum(:position) || 0) + 1
      end

      # Aggregate outputs across all completed iterations.
      #
      # For each declared loop output, find the per-iteration source value and
      # apply the matching `aggregate:` mode (or default to `last`).
      #
      # Per-iteration source resolution (v0.2 convention):
      #   1. If the LAST body step's outputs contain a key matching the loop
      #      output name, take it. (Most common shape: the loop's "result"
      #      lives in the terminal step.)
      #   2. Otherwise, scan body steps in order and use the LAST body step
      #      whose outputs contain that key. (Deterministic on duplicates.)
      #   3. If the loop output is declared with `collection: true` AND an
      #      `item_schema:`, fall back to the last body step's whole output
      #      hash projected onto the item_schema keys. This is the
      #      "fan-LLM-into-collection" shape from SPEC-v0.2 §2.9 where the
      #      body produces a structured object per iteration.
      #   4. Otherwise the iteration contributes nil for that output.
      def aggregate_outputs(outputs_decl, aggregate_rules, iteration_records, body_defs)
        return {} if outputs_decl.empty?

        last_body_id = body_defs.last && body_defs.last["id"]

        outputs_decl.each_with_object({}) do |output_field, acc|
          name = output_field["name"]
          next unless name

          per_iteration_values = iteration_records.map do |iter|
            extract_iteration_value(iter, name, last_body_id, output_field)
          end

          mode = aggregate_rules[name].to_s
          # `concat` of per-iteration objects naturally yields an array of
          # those objects; the apply_aggregate `else` branch returns values
          # as-is for non-array/non-string element types.
          acc[name] = apply_aggregate(mode, per_iteration_values)
        end
      end

      def extract_iteration_value(iteration, output_name, last_body_id, output_field = nil)
        outputs_by_id = iteration.outputs || {}
        return nil if outputs_by_id.empty?

        if last_body_id && outputs_by_id[last_body_id].is_a?(Hash) &&
           outputs_by_id[last_body_id].key?(output_name)
          return outputs_by_id[last_body_id][output_name]
        end

        # Fallback: deterministic last-body-step-with-this-key wins.
        match = nil
        match_found = false
        outputs_by_id.each do |_body_id, body_outputs|
          next unless body_outputs.is_a?(Hash)
          if body_outputs.key?(output_name)
            match = body_outputs[output_name]
            match_found = true
          end
        end
        return match if match_found

        # Collection + item_schema fallback: project the last body step's
        # entire outputs hash onto the declared item_schema keys. Lets a
        # body step that produces a structured object per iteration feed
        # directly into a `collection: true` loop output without needing
        # a wrapper step whose only job is to rename a key.
        if output_field.is_a?(Hash) &&
           output_field["collection"] == true &&
           output_field["item_schema"].is_a?(Hash) &&
           last_body_id && outputs_by_id[last_body_id].is_a?(Hash)
          last_outputs = outputs_by_id[last_body_id]
          schema_keys = output_field["item_schema"].keys.map(&:to_s)
          projection = schema_keys.each_with_object({}) do |k, h|
            h[k] = last_outputs[k] if last_outputs.key?(k)
          end
          return projection unless projection.empty?
        end

        nil
      end

      def apply_aggregate(mode, values)
        case mode
        when "concat"
          if values.empty?
            []
          elsif values.all? { |v| v.is_a?(Array) }
            values.flatten(1)
          elsif values.all? { |v| v.is_a?(String) }
            values.join
          else
            values
          end
        when "sum"
          values.compact.each do |v|
            unless v.is_a?(Numeric)
              raise StepFailure, "aggregate sum got non-numeric (#{v.class})"
            end
          end
          values.compact.sum(0)
        when "last", ""
          values.last
        else
          # Parser pre-validates modes; defensive only.
          raise StepFailure, "unknown aggregate mode #{mode.inspect}"
        end
      end
    end
  end
end
