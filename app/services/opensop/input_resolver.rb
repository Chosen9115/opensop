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
    def resolve_reference(ref)
      case ref
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
        value = ENV[key]
        raise UnresolvedReference, "env var #{key.inspect} is not set" if value.nil?
        value
      when /\Ainstance\.(.+)\z/
        key = Regexp.last_match(1)
        resolve_instance_field(key)
      else
        raise UnresolvedReference, "unrecognized reference syntax #{ref.inspect}"
      end
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
