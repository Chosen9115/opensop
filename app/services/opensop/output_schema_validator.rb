# frozen_string_literal: true

module Opensop
  # Validates and coerces a value (typically the parsed JSON returned by an
  # LLM step) against an `expected_output_schema:` declaration.
  #
  # Schema mini-grammar (SPEC-v0.2.md §2.5):
  #
  #   "string" | "number" | "boolean"   — scalars
  #   "enum[a, b, c]"                   — string must be one of the listed values
  #   "array[<type>]"                   — recursive array of inner scalar/enum/array
  #   { key: <type>, ... }              — nested object (recursive)
  #   [ <hash> ]                        — array of objects (single-element Array
  #                                       literal whose only element is the
  #                                       item-object schema)
  #
  # Coercion rules:
  #   - Numbers accept JSON numerics OR numeric strings ("0.92").
  #   - Booleans accept JSON true/false only — strings do NOT coerce.
  #   - Strings accept any JSON string.
  #   - Enums match exactly, case-sensitive.
  #   - Missing required keys -> error per missing key.
  #   - Extra keys not in schema are preserved (pass-through, no error).
  #
  # Public interface:
  #
  #   validator = Opensop::OutputSchemaValidator.new(schema)
  #   validator.validate!(value)        # => coerced value, raises Invalid on failure
  #   validator.validate(value)         # => [valid?, errors_array, coerced_value]
  #
  # No `eval`. Type expressions are parsed manually via regex/scan.
  class OutputSchemaValidator
    class Invalid < StandardError
      attr_reader :errors

      def initialize(errors)
        @errors = Array(errors)
        super(@errors.join("; "))
      end
    end

    class SchemaError < StandardError; end

    SCALAR_TYPES = %w[string number boolean].freeze
    ENUM_RE = /\Aenum\[(.+)\]\z/.freeze
    ARRAY_RE = /\Aarray\[(.+)\]\z/.freeze

    attr_reader :schema

    # @param schema [Hash] the parsed `expected_output_schema:` map
    def initialize(schema)
      raise SchemaError, "schema must be a Hash, got #{schema.class}" unless schema.is_a?(Hash)
      @schema = schema
      # Eagerly walk the schema so malformed type expressions surface at
      # construction time rather than first validation.
      validate_schema_shape!(@schema, "")
    end

    # Returns the validated value coerced to the declared types.
    # Raises {Invalid} (with `errors` attr) on failure.
    def validate!(value)
      ok, errors, coerced = validate(value)
      raise Invalid.new(errors) unless ok
      coerced
    end

    # Returns `[valid?, errors, coerced_value]`. Never raises for value
    # errors — only schema authoring errors raise (and those propagate
    # from the constructor).
    def validate(value)
      errors = []
      coerced = walk_object(@schema, value, "", errors)
      [ errors.empty?, errors, coerced ]
    end

    private

    # -- Schema shape validation -----------------------------------------

    def validate_schema_shape!(schema, path)
      unless schema.is_a?(Hash)
        raise SchemaError, "schema at #{display_path(path)} must be a Hash, got #{schema.class}"
      end
      schema.each do |key, type_expr|
        field_path = join_path(path, key.to_s)
        validate_field_type!(type_expr, field_path)
      end
    end

    def validate_field_type!(type_expr, path)
      case type_expr
      when Hash
        validate_schema_shape!(type_expr, path)
      when Array
        unless type_expr.length == 1
          raise SchemaError,
                "schema at #{display_path(path)}: array literal must have exactly one element (the item schema)"
        end
        validate_field_type!(type_expr.first, "#{path}[]")
      when String
        parse_type_expr!(type_expr, path)
      else
        raise SchemaError,
              "schema at #{display_path(path)}: type must be a String, Hash, or [Hash], got #{type_expr.class}"
      end
    end

    # Parses a String type expression and returns a normalized tag of one
    # of these forms:
    #
    #   [:scalar, "string" | "number" | "boolean"]
    #   [:enum,   ["a", "b", "c"]]
    #   [:array,  <inner tag>]
    def parse_type_expr!(expr, path)
      stripped = expr.strip
      raise SchemaError, "schema at #{display_path(path)}: empty type expression" if stripped.empty?

      if SCALAR_TYPES.include?(stripped)
        [ :scalar, stripped ]
      elsif (m = stripped.match(ENUM_RE))
        values = m[1].split(",").map(&:strip).reject(&:empty?)
        if values.empty?
          raise SchemaError, "schema at #{display_path(path)}: enum must list at least one value"
        end
        [ :enum, values ]
      elsif (m = stripped.match(ARRAY_RE))
        [ :array, parse_type_expr!(m[1].strip, "#{path}[]") ]
      else
        raise SchemaError, "schema at #{display_path(path)}: unknown type expression #{expr.inspect}"
      end
    end

    # -- Value validation ------------------------------------------------

    def walk_object(schema, value, path, errors)
      unless value.is_a?(Hash)
        errors << "#{display_path(path)}: expected object, got #{describe(value)}"
        return value
      end
      stringified = stringify_keys(value)
      result = stringified.dup

      schema.each do |key, type_expr|
        key_str = key.to_s
        field_path = join_path(path, key_str)
        unless stringified.key?(key_str)
          errors << "#{display_path(field_path)}: missing required key"
          next
        end
        result[key_str] = walk_value(type_expr, stringified[key_str], field_path, errors)
      end

      result
    end

    def walk_value(type_expr, value, path, errors)
      case type_expr
      when Hash
        walk_object(type_expr, value, path, errors)
      when Array
        # `[<item_schema>]` — array of objects/arrays/scalars expressed
        # via a Ruby array literal at the schema level.
        coerce_array_literal(type_expr.first, value, path, errors)
      else
        tag = parse_type_expr!(type_expr, path)
        apply_tag(tag, value, path, errors)
      end
    end

    def apply_tag(tag, value, path, errors)
      kind, payload = tag
      case kind
      when :scalar
        coerce_scalar(payload, value, path, errors)
      when :enum
        coerce_enum(payload, value, path, errors)
      when :array
        coerce_array(payload, value, path, errors)
      end
    end

    def coerce_scalar(type, value, path, errors)
      case type
      when "string"
        return value if value.is_a?(String)
        errors << "#{display_path(path)}: expected string, got #{describe(value)}"
        value
      when "number"
        return value if value.is_a?(Numeric) && !value.is_a?(TrueClass) && !value.is_a?(FalseClass)
        if value.is_a?(String) && numeric_string?(value)
          return value.include?(".") || value.match?(/[eE]/) ? value.to_f : value.to_i
        end
        errors << "#{display_path(path)}: expected number, got #{describe(value)}"
        value
      when "boolean"
        return value if value == true || value == false
        errors << "#{display_path(path)}: expected boolean, got #{describe(value)}"
        value
      end
    end

    def coerce_enum(values, value, path, errors)
      return value if values.include?(value)
      errors << "#{display_path(path)}: expected one of #{values.inspect}, got #{describe(value)}"
      value
    end

    # Inner type for `array[<type>]` — always a parsed tag.
    def coerce_array(inner_tag, value, path, errors)
      unless value.is_a?(Array)
        errors << "#{display_path(path)}: expected array, got #{describe(value)}"
        return value
      end
      value.each_with_index.map do |item, idx|
        apply_tag(inner_tag, item, "#{path}[#{idx}]", errors)
      end
    end

    # Inner type for `[<schema>]` — a raw schema (Hash or String).
    def coerce_array_literal(item_schema, value, path, errors)
      unless value.is_a?(Array)
        errors << "#{display_path(path)}: expected array, got #{describe(value)}"
        return value
      end
      value.each_with_index.map do |item, idx|
        walk_value(item_schema, item, "#{path}[#{idx}]", errors)
      end
    end

    # -- helpers ----------------------------------------------------------

    def stringify_keys(hash)
      hash.each_with_object({}) { |(k, v), h| h[k.to_s] = v }
    end

    def numeric_string?(str)
      Float(str)
      true
    rescue ArgumentError, TypeError
      false
    end

    def describe(value)
      case value
      when nil then "null"
      when String then value.inspect
      when Numeric, TrueClass, FalseClass then value.inspect
      when Array then "array(#{value.size})"
      when Hash then "object"
      else value.inspect
      end
    end

    def join_path(parent, key)
      parent.empty? ? key : "#{parent}.#{key}"
    end

    def display_path(path)
      path.empty? ? "(root)" : path
    end
  end
end
