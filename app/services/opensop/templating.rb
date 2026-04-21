# frozen_string_literal: true

module Opensop
  # String interpolation for webhook URLs, headers, and body templates.
  #
  # Supports `${expression}` placeholders where `expression` is one of:
  #
  #   ${callback_url}           → the full callback URL (callback mode only)
  #   ${process.inputs.X}       → a value from the instance-level inputs
  #   ${env.X}                  → ENV["X"]
  #   ${X.Y.Z}                  → drills into the step's resolved inputs hash
  #
  # Missing keys raise MissingVariable so misconfiguration fails loudly at
  # step execution rather than silently producing garbage payloads.
  #
  # NOTE: all substitution is string-level. If a body template contains
  # `"amount": "${inputs.amount}"` and the input is the number 5000, the
  # result is the string `"5000"`. Author quotes accordingly, or leave
  # `body_template` unset to send the resolved inputs as JSON with types
  # preserved.
  module Templating
    class MissingVariable < StandardError; end

    PATTERN = /\$\{([^}]+)\}/

    module_function

    def render(string, step_inputs: {}, process_inputs: {}, callback_url: nil)
      return nil if string.nil?
      return string unless string.is_a?(String)

      string.gsub(PATTERN) do
        expression = Regexp.last_match(1).strip
        resolve(
          expression,
          step_inputs: step_inputs.to_h.deep_stringify_keys,
          process_inputs: process_inputs.to_h.deep_stringify_keys,
          callback_url: callback_url
        )
      end
    end

    def resolve(expression, step_inputs:, process_inputs:, callback_url:)
      return callback_url.to_s if expression == "callback_url"

      if expression.start_with?("env.")
        key = expression.sub(/\Aenv\./, "")
        value = ENV[key]
        raise MissingVariable, "ENV[#{key.inspect}] is not set" if value.nil?
        return value
      end

      if expression.start_with?("process.inputs.")
        path = expression.sub(/\Aprocess\.inputs\./, "").split(".")
        return stringify!(walk(process_inputs, path), expression)
      end

      # Bare path — resolve against step inputs.
      path = expression.split(".")
      stringify!(walk(step_inputs, path), expression)
    end

    def walk(hash, path)
      path.inject(hash) do |cursor, key|
        raise MissingVariable, "cannot descend into non-hash at #{key.inspect}" unless cursor.is_a?(Hash)
        raise MissingVariable, "missing key #{key.inspect}" unless cursor.key?(key)
        cursor[key]
      end
    end

    def stringify!(value, expression)
      case value
      when String       then value
      when Numeric      then value.to_s
      when TrueClass    then "true"
      when FalseClass   then "false"
      when NilClass     then raise MissingVariable, "variable #{expression.inspect} resolved to nil"
      when Hash, Array  then JSON.dump(value)
      else value.to_s
      end
    end
  end
end
