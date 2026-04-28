# frozen_string_literal: true

module Opensop
  # The process engine runtime.
  # Orchestrates a Sop::Instance from start through each step until it
  # reaches completion, failure, or a waiting sub-state.
  module InstanceExecutor
    class InvalidInputs < StandardError; end
    class InvalidTransition < StandardError; end

    module_function

    # -- Public API -------------------------------------------------------

    def start(process:, inputs:, metadata: {})
      definition = process.definition
      process_block = definition["process"]
      validate_inputs!(process_block["inputs"], inputs)

      instance = nil
      ActiveRecord::Base.transaction do
        instance = Sop::Instance.create!(
          process: process,
          process_name: process.name,
          process_version: process.version,
          state: "pending",
          inputs: inputs.to_h,
          outputs: {},
          metadata: metadata.to_h
        )

        process_block["steps"].each_with_index do |step_def, idx|
          instance.steps.create!(
            step_id: step_def["id"],
            step_name: step_def["name"],
            step_type: step_def["type"],
            state: "pending",
            sub_state: nil,
            inputs: {},
            outputs: {},
            position: idx + 1,
            attempt: 1
          )
        end

        instance.update!(state: "running", started_at: Time.current)
        emit_event(instance, event_type: "instance.started",
                   data: { inputs: inputs, metadata: metadata })
      end

      advance!(instance)
      instance
    end

    def advance!(instance)
      instance.reload
      return instance if terminal?(instance)

      loop do
        step = instance.steps.where(state: "pending").order(:position).first
        break unless step

        step_def = step_definition_for(instance, step)
        unless step_def
          fail_step!(instance, step, "step definition not found for step_id=#{step.step_id.inspect}")
          break
        end

        # Evaluate `condition:` — skip step if false.
        if step_def["condition"]
          begin
            evaluator = Opensop::ConditionEvaluator.new(instance: instance)
            unless evaluator.call(step_def["condition"])
              skip_step!(instance, step, reason: "condition_false",
                         expression: step_def["condition"])
              next
            end
          rescue Opensop::ConditionEvaluator::InvalidExpression => e
            fail_step!(instance, step, "invalid condition: #{e.message}")
            break
          end
        end

        # Resolve inputs, activate step.
        begin
          resolver = Opensop::InputResolver.new(instance: instance)
          resolved_inputs = resolver.resolve(step_def)
        rescue Opensop::InputResolver::UnresolvedReference => e
          fail_step!(instance, step, "unresolved input reference: #{e.message}")
          break
        end

        ActiveRecord::Base.transaction do
          step.update!(
            state: "active",
            sub_state: "running",
            started_at: Time.current,
            inputs: resolved_inputs
          )
          emit_event(instance, step_id: step.step_id,
                     event_type: "step.started",
                     data: { inputs: resolved_inputs })
        end

        # Dispatch.
        result =
          begin
            executor_class = Opensop::StepExecutor.for(step.step_type)
            executor_class.new.call(step, instance, step_def)
          rescue StandardError => e
            fail_step!(instance, step, "#{e.class}: #{e.message}")
            return instance
          end

        if result[:outputs]
          complete_step!(instance, step, outputs: result[:outputs], decided_by: "system")
          # Step-level early exit: if the step's `exit_when:` predicate is
          # true, terminate the entire process now with `exit_outputs:`.
          if try_exit_early!(step, step_def, instance) == :exited
            return instance
          end
          next # loop, try next step
        elsif result[:waiting]
          pause_step!(instance, step, sub_state: result[:waiting])
          return instance
        else
          fail_step!(instance, step, "executor returned invalid result: #{result.inspect}")
          return instance
        end
      end

      # No more pending steps — finalize if the last step is completed/skipped.
      finalize_if_done(instance)
      instance
    end

    def submit_step(instance:, step_id:, outputs:, decided_by: "system", confidence: nil)
      instance.reload
      step = instance.steps.find_by!(step_id: step_id)

      unless step.active? || step.failed?
        raise InvalidTransition, "step #{step_id.inspect} is not awaiting submission (state=#{step.state}, sub_state=#{step.sub_state})"
      end

      step_def = step_definition_for(instance, step)
      validate_outputs!(step_def["outputs"], outputs, instance: instance) if step_def

      complete_step!(instance, step, outputs: outputs, decided_by: decided_by, confidence: confidence)
      # Step-level early exit fires here too, so a human/agent submission
      # can short-circuit the process the same way an automated step can.
      if step_def && try_exit_early!(step, step_def, instance) == :exited
        return instance
      end
      advance!(instance)
      instance
    end

    def cancel!(instance, reason: nil)
      instance.reload
      return instance if instance.cancelled? || instance.completed?

      ActiveRecord::Base.transaction do
        instance.steps.where(state: "active").find_each do |step|
          step.update!(state: "skipped", sub_state: nil,
                       completed_at: Time.current,
                       error: reason || "instance cancelled")
          emit_event(instance, step_id: step.step_id,
                     event_type: "step.skipped",
                     data: { reason: reason || "instance_cancelled" })
        end
        instance.update!(state: "cancelled", completed_at: Time.current,
                         error: reason)
        emit_event(instance, event_type: "instance.cancelled",
                   data: { reason: reason })
      end
      instance
    end

    # Public extension point: evaluate a completed step's `exit_when:`
    # predicate and, if truthy, terminate the entire process with the
    # step definition's literal `exit_outputs:`. Returns `:exited` when
    # the process was terminated, `:continue` otherwise.
    #
    # Called by `advance!` and `submit_step` automatically after every
    # successful `complete_step!`. Also exposed publicly so the loop
    # executor (which dispatches body-step executors directly without
    # routing through `advance!`) can invoke the same logic after each
    # body step completes — a body step's exit_when terminates the WHOLE
    # process per SPEC-v0.2 §2.8, not just the loop iteration.
    #
    # @param step [Sop::Step] the just-completed step
    # @param definition [Hash] the step's YAML-derived definition hash
    # @param instance [Sop::Instance] the parent instance
    # @return [Symbol] :exited or :continue
    def try_exit_early!(step, definition, instance)
      return :continue unless definition.is_a?(Hash)
      expr = definition["exit_when"]
      return :continue if expr.nil? || expr.to_s.strip.empty?

      # Per SPEC-v0.2 §2.8, `outputs.<key>` inside `exit_when:` refers to
      # the just-completed step's own outputs. Rewrite into the canonical
      # `steps.<id>.outputs.<key>` form so InputResolver (via
      # ConditionEvaluator) can resolve it from the persisted step row.
      rewritten = rewrite_outputs_refs(expr.to_s, step.step_id)

      evaluator = Opensop::ConditionEvaluator.new(instance: instance)
      truthy =
        begin
          evaluator.call(rewritten)
        rescue Opensop::ConditionEvaluator::InvalidExpression
          false
        end
      return :continue unless truthy

      exit_outputs = definition["exit_outputs"] || {}
      merged = (instance.outputs || {}).merge(exit_outputs)

      attrs = { state: "completed", outputs: merged }
      attrs[:completed_at] = Time.current if instance.respond_to?(:completed_at)

      ActiveRecord::Base.transaction do
        instance.update!(attrs)
        emit_event(instance, event_type: "instance.exited_early",
                   data: { step_id: step.step_id, exit_outputs: exit_outputs })
      end
      :exited
    end

    # Rewrite bare `outputs.<key>` references inside an exit_when expression
    # into the fully-qualified `steps.<step_id>.outputs.<key>` form so the
    # standard InputResolver / ConditionEvaluator can resolve them. We only
    # touch identifiers OUTSIDE single/double quoted string literals so a
    # comparison like `outputs.tag == 'outputs.foo'` rewrites only the LHS.
    def rewrite_outputs_refs(expr, step_id)
      out = +""
      i = 0
      n = expr.length
      while i < n
        ch = expr[i]
        if ch == "'" || ch == '"'
          # Copy the quoted literal verbatim, honoring backslash escapes.
          quote = ch
          out << ch
          i += 1
          while i < n
            c = expr[i]
            out << c
            i += 1
            if c == "\\" && i < n
              out << expr[i]
              i += 1
            elsif c == quote
              break
            end
          end
        elsif (m = expr[i..].match(/\A(?<!\w)outputs\.([A-Za-z_][A-Za-z0-9_]*)/))
          # Guard the left edge: only rewrite when not preceded by a word
          # char (so `myoutputs.x` stays untouched).
          prev = i.zero? ? "" : expr[i - 1]
          if prev =~ /\w/
            out << ch
            i += 1
          else
            out << "steps.#{step_id}.outputs.#{m[1]}"
            i += m[0].length
          end
        else
          out << ch
          i += 1
        end
      end
      out
    end

    # -- Internals --------------------------------------------------------

    def step_definition_for(instance, step)
      definition = instance.process&.definition || {}
      steps = definition.dig("process", "steps") || []
      steps.find { |s| s["id"] == step.step_id }
    end

    def terminal?(instance)
      %w[completed failed cancelled].include?(instance.state)
    end

    def validate_inputs!(schema, inputs)
      return if schema.blank?
      inputs = inputs.transform_keys(&:to_s) if inputs.respond_to?(:transform_keys)
      errors = []
      schema.each do |field|
        name = field["name"]
        if field["required"] && (!inputs.key?(name) || inputs[name].nil? || inputs[name] == "")
          errors << "missing required input #{name.inspect}"
        end
        if inputs[name] && field["type"] == "enum" && field["values"].is_a?(Array)
          unless field["values"].map(&:to_s).include?(inputs[name].to_s)
            errors << "input #{name.inspect} must be one of #{field["values"].inspect}"
          end
        end
      end
      raise InvalidInputs, errors.join("; ") if errors.any?
    end

    # Validate a step's submitted outputs against its declared schema.
    #
    # Fields marked `required_if:` are only required when the condition
    # evaluates to true against the submitted outputs themselves (useful
    # for e.g. `rejection_reason` on a judgment step: required only when
    # `decision == 'reject'`).
    def validate_outputs!(schema, outputs, instance: nil)
      return if schema.blank?
      outputs = outputs.transform_keys(&:to_s) if outputs.respond_to?(:transform_keys)

      evaluator =
        if instance
          Opensop::ConditionEvaluator.new(instance: instance, extra: outputs)
        end

      missing = schema.reject do |f|
        if outputs.key?(f["name"])
          true
        elsif f["required_if"] && evaluator
          begin
            !evaluator.call(f["required_if"])
          rescue Opensop::ConditionEvaluator::InvalidExpression
            false
          end
        else
          false
        end
      end.map { |f| f["name"] }

      if missing.any?
        raise InvalidInputs, "step outputs missing keys: #{missing.join(", ")}"
      end
    end

    def skip_step!(instance, step, reason:, expression: nil)
      ActiveRecord::Base.transaction do
        step.update!(state: "skipped", sub_state: nil,
                     started_at: step.started_at || Time.current,
                     completed_at: Time.current)
        emit_event(instance, step_id: step.step_id,
                   event_type: "step.skipped",
                   data: { reason: reason, expression: expression }.compact)
      end
    end

    def complete_step!(instance, step, outputs:, decided_by:, confidence: nil)
      ActiveRecord::Base.transaction do
        step.update!(
          state: "completed",
          sub_state: nil,
          outputs: outputs.to_h,
          decided_by: decided_by,
          confidence: confidence,
          completed_at: Time.current
        )
        emit_event(instance, step_id: step.step_id,
                   event_type: "step.completed",
                   data: { outputs: outputs, decided_by: decided_by })
      end
    end

    def pause_step!(instance, step, sub_state:)
      ActiveRecord::Base.transaction do
        step.update!(sub_state: sub_state)
        emit_event(instance, step_id: step.step_id,
                   event_type: "step.#{sub_state}",
                   data: {})
      end
    end

    def fail_step!(instance, step, error)
      Rails.logger.warn("[Opensop::InstanceExecutor] failing step=#{step.step_id}: #{error}")
      ActiveRecord::Base.transaction do
        step.update!(state: "failed", sub_state: nil,
                     error: error, completed_at: Time.current)
        emit_event(instance, step_id: step.step_id,
                   event_type: "step.failed",
                   data: { error: error })
        instance.update!(state: "failed", error: error,
                         completed_at: Time.current)
        emit_event(instance, event_type: "instance.failed",
                   data: { error: error, failed_step: step.step_id })
      end
    end

    def finalize_if_done(instance)
      instance.reload
      return if terminal?(instance)

      remaining = instance.steps.where(state: %w[pending active]).exists?
      return if remaining

      definition = instance.process&.definition || {}
      process_block = definition["process"] || {}
      outputs = resolve_process_outputs(instance, process_block["outputs"])

      ActiveRecord::Base.transaction do
        instance.update!(state: "completed", completed_at: Time.current,
                         outputs: outputs)
        emit_event(instance, event_type: "instance.completed",
                   data: { outputs: outputs })
      end
    end

    # Resolve process-level outputs with two-pass `required_if:` support.
    #
    # Pass 1: unconditionally resolve every declared output into a scratch
    #   hash. Missing references produce `nil` (swallowed).
    # Pass 2: for every field that declares `required_if:`, evaluate the
    #   condition against the scratch hash (so sibling outputs like
    #   `status` are visible). If false, drop the key entirely.
    def resolve_process_outputs(instance, output_schema)
      return {} if output_schema.blank?
      resolver = Opensop::InputResolver.new(instance: instance)

      scratch = {}
      output_schema.each do |field|
        name = field["name"]
        next unless name
        if field["from"]
          scratch[name] =
            begin
              resolver.resolve_reference(field["from"])
            rescue Opensop::InputResolver::UnresolvedReference
              nil
            end
        elsif field.key?("value")
          scratch[name] = field["value"]
        end
      end

      # Apply required_if gating. A false condition drops the key.
      evaluator = Opensop::ConditionEvaluator.new(instance: instance, extra: scratch)
      output_schema.each do |field|
        name = field["name"]
        next unless name
        cond = field["required_if"]
        next unless cond
        begin
          scratch.delete(name) unless evaluator.call(cond)
        rescue Opensop::ConditionEvaluator::InvalidExpression
          # A malformed required_if should not break completion; keep the
          # output value so the failure is visible to operators.
        end
      end

      scratch
    end

    def emit_event(instance, event_type:, step_id: nil, actor: "system", data: {})
      instance.events.create!(
        step_id: step_id,
        event_type: event_type,
        actor: actor,
        data: data || {}
      )
    end
  end
end
