# frozen_string_literal: true

require "yaml"

module Opensop
  # Parses and validates an OpenSOP process definition (version 0.1).
  #
  # Does NOT persist anything — it simply returns a validated hash
  # ready to be stored in Sop::Process#definition.
  class DefinitionParser
    SPEC_VERSION = "0.1"
    STEP_TYPES = %w[form automated judgment approval webhook subprocess notification wait].freeze
    TRIGGER_TYPES = %w[api webhook schedule manual].freeze
    TRIGGER_AUTH_SCHEMES = %w[hmac-sha256].freeze
    TRIGGER_AUTH_ENCODINGS = %w[hex base64].freeze
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
      /\Ainstance\.[A-Za-z_][A-Za-z0-9_]*\z/
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
        parsed = YAML.safe_load(input, permitted_classes: [Date, Time, Symbol], aliases: true)
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
      if hash["opensop"].to_s != SPEC_VERSION
        fail_at!("opensop", "unsupported version #{hash["opensop"].inspect} (expected #{SPEC_VERSION.inspect})")
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

    def validate_step!(step, path, ids)
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

      case step["type"]
      when "automated"
        fail_at!("#{path}.run", "automated step requires a `run` path") unless step["run"].is_a?(String) && !step["run"].strip.empty?
      when "webhook"
        validate_webhook!(step, path)
      when "subprocess"
        fail_at!("#{path}.process", "subprocess step requires a `process` name") unless step["process"].is_a?(String) && !step["process"].strip.empty?
      when "judgment"
        validate_judgment!(step, path)
      end
    end

    def validate_trigger!(process)
      trigger = process["trigger"]
      return if trigger.nil?

      fail_at!("process.trigger", "must be a mapping") unless trigger.is_a?(Hash)
      type = trigger["type"].to_s
      unless TRIGGER_TYPES.include?(type)
        fail_at!("process.trigger.type", "unknown trigger type #{type.inspect} (allowed: #{TRIGGER_TYPES.join(", ")})")
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
        unless value.is_a?(String) || value.is_a?(Numeric) || [true, false].include?(value)
          fail_at!("process.trigger.input_mapping.#{key}",
                   "must be a string, number, or boolean literal (got #{value.class})")
        end
      end
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
