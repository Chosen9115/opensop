# frozen_string_literal: true

module Opensop
  # Evaluates a *restricted* boolean expression against an Sop::Instance.
  #
  # Grammar (recursive descent):
  #   expr       := or_expr
  #   or_expr    := and_expr ('||' and_expr)*
  #   and_expr   := not_expr ('&&' not_expr)*
  #   not_expr   := '!' not_expr | compare
  #   compare    := value ((== | != | > | >= | < | <=) value)?
  #   value      := NUMBER | STRING | BOOL | NULL | REFERENCE | '(' expr ')'
  #
  # References use the same syntax as InputResolver (process.inputs.x,
  # steps.foo.outputs.bar, env.X, instance.field).
  #
  # No eval, no method calls, no string interpolation. If the expression
  # cannot be parsed, InvalidExpression is raised.
  class ConditionEvaluator
    class InvalidExpression < StandardError; end

    TOKEN_SPEC = [
      [:WS,     /\A\s+/],
      [:AND,    /\A&&/],
      [:OR,     /\A\|\|/],
      [:NOT,    /\A!(?!=)/],
      [:EQ,     /\A==/],
      [:NEQ,    /\A!=/],
      [:GTE,    /\A>=/],
      [:LTE,    /\A<=/],
      [:GT,     /\A>/],
      [:LT,     /\A</],
      [:LPAREN, /\A\(/],
      [:RPAREN, /\A\)/],
      [:NUMBER, /\A-?\d+(?:\.\d+)?/],
      [:STRING, /\A'([^'\\]*(?:\\.[^'\\]*)*)'|\A"([^"\\]*(?:\\.[^"\\]*)*)"/],
      [:IDENT,  /\A[A-Za-z_][A-Za-z0-9_.\-]*/]
    ].freeze

    attr_reader :instance

    # @param instance [Sop::Instance] used to resolve process.inputs.*,
    #   steps.*.outputs.*, instance.*, and env.* references.
    # @param extra [Hash] optional scratch hash consulted FIRST for bare
    #   identifiers (e.g. `status`) that are not qualified references.
    #   Used by `InstanceExecutor#resolve_process_outputs` to evaluate
    #   `required_if:` expressions against the freshly-resolved process
    #   outputs — the outputs hash hasn't been persisted yet so the
    #   resolver can't see it via `instance.outputs`.
    def initialize(instance:, extra: nil)
      @instance = instance
      @resolver = Opensop::InputResolver.new(instance: instance)
      @extra = extra
    end

    def call(expression)
      return true if expression.nil? || expression.to_s.strip.empty?
      tokens = tokenize(expression.to_s)
      @tokens = tokens
      @pos = 0
      result = parse_or
      unless eos?
        raise InvalidExpression, "unexpected trailing token #{peek.inspect} in #{expression.inspect}"
      end
      !!result
    end

    private

    # -- Tokenizer --------------------------------------------------------

    def tokenize(str)
      tokens = []
      pos = 0
      while pos < str.length
        slice = str[pos..]
        matched = false
        TOKEN_SPEC.each do |type, re|
          m = slice.match(re)
          next unless m
          value = m[0]
          pos += value.length
          matched = true
          next if type == :WS
          value =
            case type
            when :STRING
              # Strip enclosing quotes and unescape minimally.
              inner = m[1] || m[2] || ""
              inner.gsub(/\\(.)/, '\1')
            when :NUMBER
              value.include?(".") ? value.to_f : value.to_i
            when :IDENT
              value
            else
              value
            end
          tokens << [type, value]
          break
        end
        raise InvalidExpression, "unexpected char at offset #{pos}: #{str[pos].inspect}" unless matched
      end
      tokens
    end

    # -- Parser -----------------------------------------------------------

    def eos?
      @pos >= @tokens.length
    end

    def peek
      @tokens[@pos]
    end

    def consume(expected_type)
      tok = @tokens[@pos]
      raise InvalidExpression, "expected #{expected_type}, got EOF" if tok.nil?
      unless tok[0] == expected_type
        raise InvalidExpression, "expected #{expected_type}, got #{tok[0]} (#{tok[1].inspect})"
      end
      @pos += 1
      tok[1]
    end

    def match?(*types)
      !eos? && types.include?(@tokens[@pos][0])
    end

    def parse_or
      result = parse_and
      while match?(:OR)
        @pos += 1
        right = parse_and
        result = result || right
      end
      result
    end

    def parse_and
      result = parse_not
      while match?(:AND)
        @pos += 1
        right = parse_not
        result = result && right
      end
      result
    end

    def parse_not
      if match?(:NOT)
        @pos += 1
        val = parse_not
        !val
      else
        parse_compare
      end
    end

    def parse_compare
      left = parse_value
      if match?(:EQ, :NEQ, :GT, :GTE, :LT, :LTE)
        op_type = @tokens[@pos][0]
        @pos += 1
        right = parse_value
        apply_compare(op_type, left, right)
      else
        left
      end
    end

    def parse_value
      raise InvalidExpression, "unexpected EOF" if eos?
      type, value = @tokens[@pos]
      case type
      when :NUMBER
        @pos += 1
        value
      when :STRING
        @pos += 1
        value
      when :IDENT
        @pos += 1
        case value
        when "true" then true
        when "false" then false
        when "null", "nil" then nil
        else
          resolve_ident(value)
        end
      when :LPAREN
        @pos += 1
        inner = parse_or
        consume(:RPAREN)
        inner
      else
        raise InvalidExpression, "unexpected token #{type} (#{value.inspect})"
      end
    end

    def resolve_ident(ref)
      # Check `extra:` first for bare identifiers (e.g. "status") that are
      # not dotted/qualified references. This supports `required_if:` on
      # process-level outputs referencing sibling outputs.
      if @extra.is_a?(Hash) && !ref.include?(".")
        return @extra[ref] if @extra.key?(ref)
        return @extra[ref.to_sym] if @extra.key?(ref.to_sym)
      end
      @resolver.resolve_reference(ref)
    rescue Opensop::InputResolver::UnresolvedReference
      # An unresolved reference in a condition returns nil so comparisons
      # like `foo == 'bar'` evaluate to false rather than blowing up.
      nil
    end

    def apply_compare(op, left, right)
      case op
      when :EQ  then left == right
      when :NEQ then left != right
      when :GT  then safe_compare(left, right) { |a, b| a > b }
      when :GTE then safe_compare(left, right) { |a, b| a >= b }
      when :LT  then safe_compare(left, right) { |a, b| a < b }
      when :LTE then safe_compare(left, right) { |a, b| a <= b }
      end
    end

    def safe_compare(left, right)
      return false if left.nil? || right.nil?
      yield(left, right)
    rescue ArgumentError, NoMethodError
      false
    end
  end
end
