# frozen_string_literal: true

module Opensop
  # String interpolation for webhook URLs, headers, body templates, and
  # trigger input mappings.
  #
  # Supports `${expression}` placeholders where `expression` is one of:
  #
  #   ${callback_url}              → the full callback URL (callback mode only)
  #   ${env.X}                     → ENV["X"]
  #   ${payload.X.Y.Z}             → nested path into an inbound webhook payload
  #   ${process.inputs.X}          → instance-level input
  #   ${X.Y.Z}                     → bare path → step's resolved inputs
  #
  # Array indices are supported in dot paths: `payload.attendees.0.email`.
  #
  # Missing keys raise MissingVariable so misconfiguration fails loudly at
  # runtime rather than silently producing garbage.
  #
  # Two entry points:
  #
  #   render(string, ...)
  #     String interpolation. Always returns a String (useful for URLs,
  #     headers, and body templates). Numeric/boolean values are
  #     stringified; hashes and arrays are JSON-encoded.
  #
  #   resolve_value(value, ...)
  #     Input-mapping resolver. If the value is a String that is entirely a
  #     single `${...}` expression, returns the raw value (preserving type).
  #     If the value is a String with mixed content, falls back to render.
  #     If the value is not a String (e.g. a literal number in YAML), it is
  #     returned as-is.
  module Templating
    class MissingVariable < StandardError; end

    PATTERN = /\$\{([^}]+)\}/
    WHOLE_EXPRESSION = /\A\$\{([^}]+)\}\z/

    module_function

    def render(string, step_inputs: {}, process_inputs: {}, payload: {}, callback_url: nil)
      return nil if string.nil?
      return string unless string.is_a?(String)

      context = build_context(step_inputs, process_inputs, payload, callback_url)
      string.gsub(PATTERN) do
        expression = Regexp.last_match(1).strip
        stringify!(resolve(expression, context), expression)
      end
    end

    def resolve_value(value, step_inputs: {}, process_inputs: {}, payload: {}, callback_url: nil)
      return value unless value.is_a?(String)

      if (m = value.match(WHOLE_EXPRESSION))
        expression = m[1].strip
        context = build_context(step_inputs, process_inputs, payload, callback_url)
        resolve(expression, context)
      else
        render(
          value,
          step_inputs: step_inputs,
          process_inputs: process_inputs,
          payload: payload,
          callback_url: callback_url
        )
      end
    end

    def build_context(step_inputs, process_inputs, payload, callback_url)
      {
        step_inputs:    normalize(step_inputs),
        process_inputs: normalize(process_inputs),
        payload:        normalize(payload),
        callback_url:   callback_url
      }
    end

    def normalize(value)
      case value
      when Hash  then value.deep_stringify_keys
      when Array then value.map { |v| v.is_a?(Hash) ? v.deep_stringify_keys : v }
      else value
      end
    end

    def resolve(expression, context)
      return context[:callback_url].to_s if expression == "callback_url"

      if expression.start_with?("env.")
        key = expression.sub(/\Aenv\./, "")
        value = ENV[key]
        raise MissingVariable, "ENV[#{key.inspect}] is not set" if value.nil?
        return value
      end

      if expression.start_with?("payload.")
        path = expression.sub(/\Apayload\./, "").split(".")
        return walk(context[:payload], path, expression)
      end

      if expression.start_with?("process.inputs.")
        path = expression.sub(/\Aprocess\.inputs\./, "").split(".")
        return walk(context[:process_inputs], path, expression)
      end

      # Bare path — resolve against step inputs.
      path = expression.split(".")
      walk(context[:step_inputs], path, expression)
    end

    def walk(target, path, expression)
      path.inject(target) do |cursor, key|
        case cursor
        when Array
          idx = begin
            Integer(key)
          rescue ArgumentError, TypeError
            raise MissingVariable, "cannot index array with non-integer #{key.inspect} in #{expression.inspect}"
          end
          if idx < 0 || idx >= cursor.size
            raise MissingVariable, "index #{idx} out of bounds (size=#{cursor.size}) in #{expression.inspect}"
          end
          cursor[idx]
        when Hash
          raise MissingVariable, "missing key #{key.inspect} in #{expression.inspect}" unless cursor.key?(key)
          cursor[key]
        when nil
          raise MissingVariable, "cannot descend into nil at #{key.inspect} in #{expression.inspect}"
        else
          raise MissingVariable, "cannot descend into #{cursor.class} at #{key.inspect} in #{expression.inspect}"
        end
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
