# frozen_string_literal: true

module Opensop
  # Builds a Claude-ready XML-tagged debugging prompt for a failed process instance.
  #
  # Usage:
  #   prompt = Opensop::DebugPromptBuilder.new(instance: instance, step: step).call
  #   # => String — paste into Claude to get debugging help
  #
  # The builder is pure formatting — no external service calls.
  class DebugPromptBuilder
    YAML_MAX_BYTES   = 4_096
    TRACE_MAX_BYTES  = 8_192
    JSON_MAX_BYTES   = 2_048
    MAX_FAILED_STEPS = 3

    # @param instance [Sop::Instance] required
    # @param step [Sop::Step, nil] optional — when given, prompt focuses on that step
    def initialize(instance:, step: nil)
      @instance = instance
      @step = step
    end

    # @return [String] complete XML-tagged prompt ready to paste into Claude
    def call
      <<~PROMPT.rstrip
        I need help debugging an error in an OpenSOP process instance.
        OpenSOP is an open standard for defining business processes as YAML and
        exposing them as REST APIs. The process definition IS the API contract.

        <instance>
          <process_name>#{@instance.process_name}</process_name>
          <process_version>#{@instance.process_version}</process_version>
          <instance_id>#{@instance.id}</instance_id>
          <started_at>#{format_field(@instance.started_at&.iso8601)}</started_at>
          <status>#{@instance.state}</status>
        </instance>

        <process_definition>
        <![CDATA[
        #{process_yaml}
        ]]>
        </process_definition>

        #{failed_steps_section}

        <instance_inputs><![CDATA[
        #{truncate_json(@instance.inputs)}
        ]]></instance_inputs>

        <request>
        Please diagnose the root cause of this failure and suggest a fix. Consider:
        (1) YAML definition correctness, (2) input/output schema mismatches,
        (3) the step type's expected behavior per OpenSOP spec, (4) whether retrying would help.
        </request>
      PROMPT
    end

    private

    def format_field(value)
      value.presence || "[unavailable]"
    end

    # -------------------------------------------------------------------------
    # Process YAML
    # -------------------------------------------------------------------------

    def process_yaml
      if @instance.process.nil?
        "[unavailable: process not found in registry]"
      else
        yaml = YAML.dump(@instance.process.definition)
        truncate_yaml(yaml)
      end
    end

    def truncate_yaml(yaml)
      return yaml if yaml.bytesize <= YAML_MAX_BYTES

      cutoff = YAML_MAX_BYTES - 30
      yaml.byteslice(0, cutoff) + "\n# ... [truncated]\n"
    end

    # -------------------------------------------------------------------------
    # Failed steps
    # -------------------------------------------------------------------------

    def failed_steps_section
      steps = steps_to_render

      if steps.empty?
        "<failed_steps></failed_steps>"
      else
        inner = steps.map { |s| render_step(s) }.join("\n")
        "<failed_steps>\n#{inner}\n</failed_steps>"
      end
    end

    def steps_to_render
      if @step
        [ @step ]
      else
        @instance.steps.select { |s| s.error.present? }.first(MAX_FAILED_STEPS)
      end
    end

    def render_step(step)
      <<~STEP.rstrip
          <step id="#{step.step_id}" type="#{step.step_type}" attempt="#{step.attempt}">
            <status>#{step.state}</status>
            <sub_state>#{format_field(step.sub_state)}</sub_state>
            <error><![CDATA[
        #{truncate_trace(step.error.to_s)}
            ]]></error>
            <inputs><![CDATA[
        #{truncate_json(step.inputs)}
            ]]></inputs>
            <outputs><![CDATA[
        #{truncate_json(step.outputs)}
            ]]></outputs>
          </step>
      STEP
    end

    # -------------------------------------------------------------------------
    # Truncation helpers
    # -------------------------------------------------------------------------

    def truncate_trace(trace)
      escaped = escape_cdata(trace)
      return escaped if escaped.bytesize <= TRACE_MAX_BYTES

      half = TRACE_MAX_BYTES / 2
      escaped.byteslice(0, half) + "\n... [truncated middle] ...\n" + escaped.byteslice(-half, half).to_s
    end

    def truncate_json(value)
      json = JSON.pretty_generate(value || {})
      if json.bytesize > JSON_MAX_BYTES
        JSON.pretty_generate({ "_truncated" => true, "size_bytes" => json.bytesize })
      else
        escape_cdata(json)
      end
    end

    def escape_cdata(str)
      str.to_s.gsub("]]>", "]]]]><![CDATA[>")
    end
  end
end
