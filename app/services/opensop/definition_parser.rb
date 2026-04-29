# frozen_string_literal: true

require "yaml"

module Opensop
  # Parses and validates an OpenSOP process definition (version 0.1 or 0.2).
  #
  # Does NOT persist anything — it simply returns a validated hash
  # ready to be stored in Sop::Process#definition.
  class DefinitionParser
    SPEC_VERSION = "0.1"
    SUPPORTED_SPEC_VERSIONS = %w[0.1 0.2].freeze
    STEP_TYPES = %w[form automated judgment approval webhook subprocess notification wait llm loop].freeze
    AUTOMATED_VALIDATION_MODES = %w[lenient strict].freeze
    TRIGGER_TYPES = %w[api webhook schedule manual interval].freeze
    INTERVAL_FORMAT = /\A(\d+)([smhd])\z/
    INTERVAL_UNIT_SECONDS = { "s" => 1, "m" => 60, "h" => 3600, "d" => 86_400 }.freeze
    INTERVAL_MIN_SECONDS = 5
    TRIGGER_AUTH_SCHEMES = %w[hmac-sha256].freeze
    TRIGGER_AUTH_ENCODINGS = %w[hex base64].freeze
    LOOP_VARIANT_KEYS = %w[for_each repeat_until while].freeze
    LOOP_AGGREGATE_MODES = %w[sum concat last].freeze
    LOOP_DEFAULT_MAX_ITERATIONS = 1000
    # `loop.max_iterations:` accepts a literal positive Integer OR a template
    # string of the shape `{{ process.inputs.<name> }}` resolved at instance
    # start time. See `validate_loop!` and `StepExecutors::Loop#call`.
    LOOP_MAX_ITERATIONS_TEMPLATE_FORMAT = /\A\{\{\s*process\.inputs\.([A-Za-z_][A-Za-z0-9_]*)\s*\}\}\z/
    FIELD_TYPES = %w[
      string number boolean enum date datetime
      file file[] string[] object reference currency
    ].freeze
    WEBHOOK_RESPONSE_MODES = %w[sync callback poll].freeze
    STEP_ID_FORMAT = /\A[a-z0-9][a-z0-9_-]*\z/
    REFERENCE_FORMATS = [
      /\Aprocess\.inputs\.[A-Za-z_][A-Za-z0-9_]*\z/,
      /\Asteps\.[a-z0-9][a-z0-9_-]*\.outputs\.[A-Za-z_][A-Za-z0-9_]*\z/,
      /\Aenv\.[A-Za-z_][A-Za-z0-9_]*\z/,
      /\Ainstance\.[A-Za-z_][A-Za-z0-9_]*\z/,
      # `loop.<name>` references the loop executor's per-iteration variable
      # (the `as:` binding plus `index`). Body steps inside a `loop:` use this.
      /\Aloop\.[A-Za-z_][A-Za-z0-9_]*\z/
    ].freeze

    class InvalidDefinition < StandardError; end

    Result = Struct.new(:ok?, :value, :error)

    def self.call(yaml_or_hash)
      new(yaml_or_hash).call
    end

    def initialize(yaml_or_hash)
      @input = yaml_or_hash
    end

    def call
      hash = coerce_to_hash(@input)
      validate_top_level!(hash)
      validate_process!(hash["process"])
      Result.new(true, hash, nil)
    end

    private

    def coerce_to_hash(input)
      case input
      when String
        parsed = YAML.safe_load(input, permitted_classes: [ Date, Time, Symbol ], aliases: true)
        raise InvalidDefinition, "definition is empty or not a YAML mapping" unless parsed.is_a?(Hash)
        parsed
      when Hash
        # Stringify keys for consistent access.
        deep_stringify(input)
      else
        raise InvalidDefinition, "expected YAML string or Hash, got #{input.class}"
      end
    end

    def deep_stringify(obj)
      case obj
      when Hash
        obj.each_with_object({}) { |(k, v), acc| acc[k.to_s] = deep_stringify(v) }
      when Array
        obj.map { |v| deep_stringify(v) }
      else
        obj
      end
    end

    def validate_top_level!(hash)
      fail_at!("opensop", "missing spec version key") unless hash.key?("opensop")
      version = hash["opensop"].to_s
      unless SUPPORTED_SPEC_VERSIONS.include?(version)
        fail_at!("opensop", "unsupported version #{hash["opensop"].inspect} (expected one of #{SUPPORTED_SPEC_VERSIONS.inspect})")
      end
      fail_at!("process", "missing process block") unless hash["process"].is_a?(Hash)
    end

    def validate_process!(process)
      require_string!(process, "name", "process.name")
      fail_at!("process.name", "must be non-empty") if process["name"].to_s.strip.empty?
      require_string!(process, "version", "process.version")

      validate_trigger!(process)

      validate_optional_array!(process, "inputs", "process.inputs") { |field, i| validate_field!(field, "process.inputs[#{i}]") }
      validate_optional_array!(process, "outputs", "process.outputs") { |field, i| validate_field!(field, "process.outputs[#{i}]", require_source_or_literal: true) }

      if process["tags"] && !process["tags"].is_a?(Array)
        fail_at!("process.tags", "must be an array of strings")
      end

      # v0.2 process-level passthrough fields. We don't enforce inner shape yet;
      # we just confirm the gross types so unknown-key checks (when added later)
      # don't reject them, and so obvious typos like `post_review: "foo"` fail.
      if process.key?("post_review") && !process["post_review"].is_a?(Hash)
        fail_at!("process.post_review", "must be a mapping")
      end

      if process.key?("shared_state_writes")
        sws = process["shared_state_writes"]
        unless sws.is_a?(Array) && sws.all? { |k| k.is_a?(String) && !k.strip.empty? }
          fail_at!("process.shared_state_writes", "must be an array of non-empty strings")
        end
      end

      steps = process["steps"]
      if steps.nil?
        process["steps"] = []
      else
        fail_at!("process.steps", "must be an array") unless steps.is_a?(Array)
      end

      ids = Set.new
      process["steps"].each_with_index do |step, idx|
        path = "process.steps[#{idx}]"
        fail_at!(path, "must be a mapping") unless step.is_a?(Hash)
        validate_step!(step, path, ids)
      end
    end

    def validate_step!(step, path, ids, allow_loop: true)
      require_string!(step, "id", "#{path}.id")
      unless step["id"].to_s.match?(STEP_ID_FORMAT)
        fail_at!("#{path}.id", "invalid format (must match /[a-z0-9][a-z0-9_-]*/)")
      end
      if ids.include?(step["id"])
        fail_at!("#{path}.id", "duplicate step id #{step["id"].inspect}")
      end
      ids << step["id"]

      require_string!(step, "name", "#{path}.name")
      require_string!(step, "type", "#{path}.type")
      unless STEP_TYPES.include?(step["type"])
        fail_at!("#{path}.type", "unknown step type #{step["type"].inspect} (allowed: #{STEP_TYPES.join(", ")})")
      end

      validate_optional_array!(step, "inputs", "#{path}.inputs") do |field, i|
        validate_field!(field, "#{path}.inputs[#{i}]", allow_from: true)
      end
      validate_optional_array!(step, "outputs", "#{path}.outputs") do |field, i|
        validate_field!(field, "#{path}.outputs[#{i}]")
      end

      if step["condition"]
        fail_at!("#{path}.condition", "must be a string") unless step["condition"].is_a?(String)
      end

      validate_exit_when!(step, path)

      case step["type"]
      when "automated"
        # `run:` is optional — omitting it means the step waits for an external worker.
        validate_tools!(step, path)
        validate_automated_validation!(step, path)
      when "webhook"
        validate_webhook!(step, path)
      when "subprocess"
        fail_at!("#{path}.process", "subprocess step requires a `process` name") unless step["process"].is_a?(String) && !step["process"].strip.empty?
      when "judgment"
        validate_judgment!(step, path)
      when "llm"
        validate_llm!(step, path)
      when "loop"
        unless allow_loop
          fail_at!(path, "nested loop steps are not supported in v0.2")
        end
        validate_loop!(step, path, ids)
      end
    end

    # `exit_when:` (v0.2 §2.8) — optional predicate string that, when true at
    # step end, terminates the entire process with the literal exit_outputs.
    # We only shape-check here; the predicate itself is evaluated at runtime.
    def validate_exit_when!(step, path)
      has_when = step.key?("exit_when")
      has_outputs = step.key?("exit_outputs")

      if has_when
        unless step["exit_when"].is_a?(String) && !step["exit_when"].strip.empty?
          fail_at!("#{path}.exit_when", "must be a non-empty string predicate")
        end
        unless step["exit_outputs"].is_a?(Hash)
          fail_at!(path, "step '#{step["id"]}' has exit_when: but no exit_outputs: hash")
        end
      elsif has_outputs
        fail_at!(path, "step '#{step["id"]}' has exit_outputs: without exit_when:")
      end
    end

    # `loop:` step (v0.2 §2.9). Validates the loop block + body steps.
    # Nested loops are explicitly disallowed in v0.2.
    def validate_loop!(step, path, ids)
      block = step["loop"]
      unless block.is_a?(Hash)
        fail_at!("#{path}.loop", "loop step requires a `loop` block")
      end

      variant_keys = LOOP_VARIANT_KEYS.select { |k| block.key?(k) }
      if variant_keys.empty?
        fail_at!("#{path}.loop", "must specify exactly one of: #{LOOP_VARIANT_KEYS.join(", ")}")
      elsif variant_keys.size > 1
        fail_at!("#{path}.loop",
                 "must specify exactly one of: #{LOOP_VARIANT_KEYS.join(", ")} (got #{variant_keys.join(", ")})")
      end

      variant = variant_keys.first
      value = block[variant]
      unless value.is_a?(String) && !value.strip.empty?
        fail_at!("#{path}.loop.#{variant}", "must be a non-empty string")
      end

      # `as:` defaults to "item"
      if block.key?("as")
        unless block["as"].is_a?(String) && !block["as"].strip.empty?
          fail_at!("#{path}.loop.as", "must be a non-empty string")
        end
      else
        block["as"] = "item"
      end

      # `max_iterations:` is required for repeat_until/while, optional for for_each.
      # Accepts a literal positive Integer or a `{{ process.inputs.<name> }}`
      # template string resolved at instance start.
      if block.key?("max_iterations")
        mi = block["max_iterations"]
        is_int = mi.is_a?(Integer) && mi > 0
        is_tmpl = mi.is_a?(String) && mi.match?(LOOP_MAX_ITERATIONS_TEMPLATE_FORMAT)
        unless is_int || is_tmpl
          fail_at!("#{path}.loop.max_iterations",
                   "must be a positive integer or a `{{ process.inputs.<name> }}` template string")
        end
      else
        if variant == "for_each"
          block["max_iterations"] = LOOP_DEFAULT_MAX_ITERATIONS
        else
          fail_at!("#{path}.loop.max_iterations",
                   "required for #{variant}: loops")
        end
      end

      if block.key?("aggregate")
        agg = block["aggregate"]
        unless agg.is_a?(Hash) && !agg.empty?
          fail_at!("#{path}.loop.aggregate", "must be a non-empty mapping of output_name => mode")
        end
        agg.each do |output_name, mode|
          unless output_name.is_a?(String) && !output_name.strip.empty?
            fail_at!("#{path}.loop.aggregate", "keys must be non-empty strings")
          end
          unless LOOP_AGGREGATE_MODES.include?(mode.to_s)
            fail_at!("#{path}.loop.aggregate.#{output_name}",
                     "must be one of: #{LOOP_AGGREGATE_MODES.join(" | ")} (got #{mode.inspect})")
          end
        end
      end

      body = step["body"]
      unless body.is_a?(Array) && !body.empty?
        fail_at!("#{path}.body", "loop step requires a non-empty `body:` array of steps")
      end

      body.each_with_index do |body_step, i|
        body_path = "#{path}.body[#{i}]"
        fail_at!(body_path, "must be a mapping") unless body_step.is_a?(Hash)
        validate_step!(body_step, body_path, ids, allow_loop: false)
      end
    end

    # `validation:` on `automated` steps (v0.2 §2.14) — opt-in strict mode for
    # presence-checking declared output names against the script's stdout JSON.
    # Default is "lenient" (current behavior: missing keys silently become nil).
    # When "strict", the executor raises StepFailure if any declared output
    # `name` is absent from the parsed Hash. Extra keys are still permitted in
    # both modes.
    def validate_automated_validation!(step, path)
      if step.key?("validation")
        mode = step["validation"]
        unless mode.is_a?(String) && AUTOMATED_VALIDATION_MODES.include?(mode)
          fail_at!("#{path}.validation",
                   "must be one of #{AUTOMATED_VALIDATION_MODES.join(" | ")} (got #{mode.inspect})")
        end
      else
        step["validation"] = "lenient"
      end
    end

    # `tools:` (v0.2 §2.6) — array of capability names. The runtime enforces
    # them at execution time; here we only check shape and surface the value
    # back unchanged.
    def validate_tools!(step, path)
      return unless step.key?("tools")
      tools = step["tools"]
      unless tools.is_a?(Array) && tools.all? { |t| t.is_a?(String) && !t.strip.empty? }
        fail_at!("#{path}.tools", "must be an array of non-empty strings")
      end
    end

    # `llm` step (v0.2 §2.5).
    def validate_llm!(step, path)
      require_string!(step, "model", "#{path}.model")
      fail_at!("#{path}.model", "must be non-empty") if step["model"].to_s.strip.empty?

      has_prompt = step.key?("prompt")
      has_prompt_file = step.key?("prompt_file")
      if has_prompt && has_prompt_file
        fail_at!(path, "llm step '#{step["id"]}' requires either prompt: or prompt_file:, not both")
      elsif !has_prompt && !has_prompt_file
        fail_at!(path, "llm step '#{step["id"]}' requires either prompt: or prompt_file:, not both")
      end

      if has_prompt
        unless step["prompt"].is_a?(String) && !step["prompt"].strip.empty?
          fail_at!("#{path}.prompt", "must be a non-empty string")
        end
      end
      if has_prompt_file
        unless step["prompt_file"].is_a?(String) && !step["prompt_file"].strip.empty?
          fail_at!("#{path}.prompt_file", "must be a non-empty string path")
        end
      end

      schema = step["expected_output_schema"]
      unless schema.is_a?(Hash) && !schema.empty?
        fail_at!("#{path}.expected_output_schema", "required and must be a non-empty mapping")
      end

      validate_tools!(step, path)

      if step.key?("retry_on_incomplete")
        unless [ true, false ].include?(step["retry_on_incomplete"])
          fail_at!("#{path}.retry_on_incomplete", "must be a boolean")
        end
      end

      if step.key?("max_retries")
        mr = step["max_retries"]
        unless mr.is_a?(Integer) && mr >= 0
          fail_at!("#{path}.max_retries", "must be a non-negative integer")
        end
      end

      # Apply defaults so downstream consumers don't repeat the logic.
      step["tools"] = [] unless step.key?("tools")
      step["retry_on_incomplete"] = true unless step.key?("retry_on_incomplete")
      step["max_retries"] = 2 unless step.key?("max_retries")
    end

    def validate_trigger!(process)
      trigger = process["trigger"]
      return if trigger.nil?

      fail_at!("process.trigger", "must be a mapping") unless trigger.is_a?(Hash)
      type = trigger["type"].to_s
      unless TRIGGER_TYPES.include?(type)
        fail_at!("process.trigger.type", "unknown trigger type #{type.inspect} (allowed: #{TRIGGER_TYPES.join(", ")})")
      end

      if type == "interval"
        validate_interval_trigger!(trigger)
        return
      end

      return unless type == "webhook"

      auth = trigger["auth"]
      fail_at!("process.trigger.auth", "webhook trigger requires an `auth` block") unless auth.is_a?(Hash)

      scheme = auth["scheme"].to_s
      unless TRIGGER_AUTH_SCHEMES.include?(scheme)
        fail_at!("process.trigger.auth.scheme",
                 "unsupported scheme #{scheme.inspect} (allowed: #{TRIGGER_AUTH_SCHEMES.join(", ")})")
      end

      %w[secret_env header].each do |key|
        unless auth[key].is_a?(String) && !auth[key].strip.empty?
          fail_at!("process.trigger.auth.#{key}", "required and must be a non-empty string")
        end
      end

      if auth.key?("encoding")
        unless TRIGGER_AUTH_ENCODINGS.include?(auth["encoding"].to_s)
          fail_at!("process.trigger.auth.encoding",
                   "unsupported encoding #{auth["encoding"].inspect} (allowed: #{TRIGGER_AUTH_ENCODINGS.join(", ")})")
        end
      end

      if auth.key?("prefix")
        fail_at!("process.trigger.auth.prefix", "must be a string") unless auth["prefix"].is_a?(String)
      end

      mapping = trigger["input_mapping"]
      return if mapping.nil?

      fail_at!("process.trigger.input_mapping", "must be a mapping") unless mapping.is_a?(Hash)
      mapping.each do |key, value|
        unless key.is_a?(String) && !key.strip.empty?
          fail_at!("process.trigger.input_mapping", "keys must be non-empty strings")
        end
        # Values can be literals (strings, numbers, booleans) or ${...}
        # expressions. No further validation beyond type checks.
        unless value.is_a?(String) || value.is_a?(Numeric) || [ true, false ].include?(value)
          fail_at!("process.trigger.input_mapping.#{key}",
                   "must be a string, number, or boolean literal (got #{value.class})")
        end
      end
    end

    # `trigger.type: interval` (SPEC-v0.2.md §2.10) — parser-only support for
    # sub-minute cadence. The runtime scheduler isn't wired yet; this method
    # validates shape, parses the duration, and stores `interval_seconds:` on
    # the trigger hash so the future scheduler can consume it directly.
    def validate_interval_trigger!(trigger)
      raw = trigger["interval"]
      unless raw.is_a?(String) && !raw.strip.empty?
        fail_at!("process.trigger.interval",
                 "required and must be a non-empty string (e.g. '30s', '5m')")
      end

      m = raw.strip.match(INTERVAL_FORMAT)
      unless m
        fail_at!("process.trigger.interval",
                 "malformed interval #{raw.inspect}: expected `<positive-int><unit>` " \
                 "where unit is one of #{INTERVAL_UNIT_SECONDS.keys.join(", ")} (e.g. '30s', '5m', '1h')")
      end

      amount = m[1].to_i
      unit   = m[2]
      seconds = amount * INTERVAL_UNIT_SECONDS.fetch(unit)

      if seconds < INTERVAL_MIN_SECONDS
        fail_at!("process.trigger.interval",
                 "#{raw.inspect} is below the 5s minimum per SPEC-v0.2.md §2.10 (got #{seconds}s)")
      end

      trigger["interval_seconds"] = seconds
    end

    def validate_webhook!(step, path)
      block = step["webhook"]
      fail_at!("#{path}.webhook", "webhook step requires a `webhook` block") unless block.is_a?(Hash)
      %w[method url response_mode].each do |key|
        unless block[key].is_a?(String) && !block[key].strip.empty?
          fail_at!("#{path}.webhook.#{key}", "required and must be a non-empty string")
        end
      end
      unless WEBHOOK_RESPONSE_MODES.include?(block["response_mode"])
        fail_at!("#{path}.webhook.response_mode", "must be one of #{WEBHOOK_RESPONSE_MODES.join(", ")}")
      end
    end

    def validate_judgment!(step, path)
      block = step["judgment"]
      return if block.nil?
      fail_at!("#{path}.judgment", "must be a mapping") unless block.is_a?(Hash)
      if block.key?("confidence_threshold")
        threshold = block["confidence_threshold"]
        unless threshold.is_a?(Numeric) && threshold >= 0 && threshold <= 1
          fail_at!("#{path}.judgment.confidence_threshold", "must be a number between 0 and 1")
        end
      end
    end

    def validate_field!(field, path, allow_from: false, require_source_or_literal: false)
      fail_at!(path, "must be a mapping") unless field.is_a?(Hash)
      require_string!(field, "name", "#{path}.name")

      if field["type"]
        type = field["type"].to_s
        unless FIELD_TYPES.include?(type) || type == "string[]" || type == "file[]"
          fail_at!("#{path}.type", "unknown field type #{type.inspect}")
        end
      end

      if field["from"]
        fail_at!("#{path}.from", "must be a string") unless field["from"].is_a?(String)
        unless REFERENCE_FORMATS.any? { |re| field["from"].match?(re) }
          fail_at!("#{path}.from", "unrecognized reference syntax #{field["from"].inspect}")
        end
      end

      if field["required_if"]
        fail_at!("#{path}.required_if", "must be a string") unless field["required_if"].is_a?(String)
      end

      if field["values"]
        fail_at!("#{path}.values", "must be an array") unless field["values"].is_a?(Array)
      end

      # v0.2 §2.7 — collection outputs. Accepted on any field; in practice only
      # meaningful on outputs, but the parser doesn't restrict by location.
      if field.key?("collection")
        unless [ true, false ].include?(field["collection"])
          fail_at!("#{path}.collection", "must be a boolean")
        end
      end

      if field["collection"] == true
        unless field["item_schema"].is_a?(Hash) && !field["item_schema"].empty?
          fail_at!(path, "output '#{field["name"]}' has collection: true but no item_schema")
        end
      elsif field.key?("item_schema") && !field["item_schema"].is_a?(Hash)
        # If someone supplies item_schema without collection: true, still type-check it.
        fail_at!("#{path}.item_schema", "must be a mapping")
      end
    end

    def validate_optional_array!(hash, key, path)
      return unless hash.key?(key)
      value = hash[key]
      fail_at!(path, "must be an array") unless value.is_a?(Array)
      value.each_with_index { |item, i| yield item, i }
    end

    def require_string!(hash, key, path)
      unless hash[key].is_a?(String)
        fail_at!(path, "required string")
      end
    end

    def fail_at!(path, message)
      raise InvalidDefinition, "#{path}: #{message}"
    end
  end
end
