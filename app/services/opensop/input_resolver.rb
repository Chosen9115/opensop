# frozen_string_literal: true

module Opensop
  # Resolves the `inputs:` array on a step definition into a plain hash
  # of { name => value } using the `from:` reference syntax defined in
  # SPEC §2.5.
  class InputResolver
    class UnresolvedReference < StandardError; end

    attr_reader :instance

    def initialize(instance:)
      @instance = instance
    end

    def resolve(step_definition)
      inputs = Array(step_definition["inputs"])
      inputs.each_with_object({}) do |field, acc|
        name = field["name"]
        next unless name
        acc[name] = resolve_field(field)
      end
    end

    # Resolve a bare reference string (used by ConditionEvaluator).
    # Returns the value, or raises UnresolvedReference.
    #
    # Supports an optional trailing collection selector when the resolved
    # value is an array (typically from a `collection: true` output, SPEC v0.2 §2.7):
    #   * `path[*]`           -> the whole array
    #   * `path[<n>]`         -> indexed access (out-of-range returns nil)
    #   * `path[*].<field>`   -> pluck `<field>` from each item
    def resolve_reference(ref)
      base_ref, selector = split_selector(ref)

      value =
        case base_ref
        when /\Aprocess\.inputs\.(.+)\z/
          key = Regexp.last_match(1)
          fetch_hash_value(instance.inputs, key, "process.inputs.#{key}")
        when /\Asteps\.([a-z0-9][a-z0-9_-]*)\.outputs\.(.+)\z/
          step_id = Regexp.last_match(1)
          key = Regexp.last_match(2)
          step = instance.steps.find_by(step_id: step_id)
          raise UnresolvedReference, "unknown step #{step_id.inspect}" unless step
          unless step.completed?
            raise UnresolvedReference, "step #{step_id.inspect} has not completed (state=#{step.state})"
          end
          fetch_hash_value(step.outputs, key, "steps.#{step_id}.outputs.#{key}")
        when /\Aenv\.(.+)\z/
          key = Regexp.last_match(1)
          v = ENV[key]
          raise UnresolvedReference, "env var #{key.inspect} is not set" if v.nil?
          v
        when /\Ainstance\.(.+)\z/
          key = Regexp.last_match(1)
          resolve_instance_field(key)
        else
          raise UnresolvedReference, "unrecognized reference syntax #{ref.inspect}"
        end

      selector ? apply_selector(value, selector, ref) : value
    end

    private

    def resolve_field(field)
      if field.key?("from")
        begin
          resolve_reference(field["from"])
        rescue UnresolvedReference
          if field.key?("default")
            field["default"]
          else
            raise
          end
        end
      elsif field.key?("value")
        field["value"]
      elsif field.key?("default")
        field["default"]
      else
        nil
      end
    end

    # Splits a reference into [base_ref, selector_string] where the selector
    # is everything from the first `[` onward (or nil if there is no `[`).
    # Examples:
    #   "steps.x.outputs.y"          -> ["steps.x.outputs.y", nil]
    #   "steps.x.outputs.y[*]"       -> ["steps.x.outputs.y", "[*]"]
    #   "steps.x.outputs.y[0]"       -> ["steps.x.outputs.y", "[0]"]
    #   "steps.x.outputs.y[*].label" -> ["steps.x.outputs.y", "[*].label"]
    def split_selector(ref)
      idx = ref.index("[")
      return [ ref, nil ] unless idx
      [ ref[0...idx], ref[idx..] ]
    end

    # Applies a parsed collection selector to `value`. `original_ref` is used
    # only for error messages.
    def apply_selector(value, selector, original_ref)
      # Reject nested [*] selectors early — only one trailing wildcard supported in v0.2.
      if selector.scan("[*]").length > 1
        raise UnresolvedReference, "nested [*] selectors are not supported in v0.2"
      end

      case selector
      when /\A\[\*\]\z/
        ensure_array!(value, original_ref)
        value
      when /\A\[(\d+)\]\z/
        ensure_array!(value, original_ref)
        value[Regexp.last_match(1).to_i]
      when /\A\[\*\]\.([a-zA-Z_][a-zA-Z0-9_]*)\z/
        field = Regexp.last_match(1)
        ensure_array!(value, original_ref)
        # Pluck `field` from each item. Items missing the field are dropped
        # (no nil placeholders), per v0.2 §2.7 selector semantics.
        value.each_with_object([]) do |item, acc|
          next unless item.is_a?(Hash)
          if item.key?(field)
            acc << item[field]
          elsif item.key?(field.to_sym)
            acc << item[field.to_sym]
          end
        end
      else
        raise UnresolvedReference,
              "unrecognized collection selector in reference #{original_ref.inspect}"
      end
    end

    def ensure_array!(value, original_ref)
      return if value.is_a?(Array)
      raise UnresolvedReference,
            "collection selector applied to non-array value in reference #{original_ref.inspect}"
    end

    def fetch_hash_value(container, key, full_path)
      container = container || {}
      # Try string key first, then symbol.
      if container.is_a?(Hash)
        return container[key] if container.key?(key)
        return container[key.to_sym] if container.key?(key.to_sym)
      end
      raise UnresolvedReference, "#{full_path} is not set"
    end

    def resolve_instance_field(key)
      # Direct column access when available.
      column_value =
        case key
        when "id" then instance.id
        when "started_at" then instance.started_at
        when "completed_at" then instance.completed_at
        when "state" then instance.state
        when "process_name" then instance.process_name
        when "process_version" then instance.process_version
        end
      return column_value if column_value

      metadata = instance.metadata || {}
      if metadata.key?(key)
        metadata[key]
      elsif metadata.key?(key.to_sym)
        metadata[key.to_sym]
      else
        raise UnresolvedReference, "instance.#{key} is not set"
      end
    end
  end
end
