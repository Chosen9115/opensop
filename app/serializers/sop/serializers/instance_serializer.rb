module Sop
  module Serializers
    # Serializes a Sop::Instance along with its ordered steps. Shape is
    # stable enough to be consumed by both API clients and the UI.
    class InstanceSerializer
      def initialize(instance, include_steps: true)
        @instance = instance
        @include_steps = include_steps
      end

      def as_json(*)
        payload = {
          id: @instance.id,
          process: {
            name: @instance.process_name,
            version: @instance.process_version
          },
          state: @instance.state,
          inputs: @instance.inputs || {},
          outputs: @instance.outputs || {},
          metadata: @instance.metadata || {},
          started_at: @instance.started_at&.iso8601,
          completed_at: @instance.completed_at&.iso8601,
          error: @instance.error,
          links: {
            self: "/sop/#{@instance.process_name}/#{@instance.id}",
            steps: "/sop/#{@instance.process_name}/#{@instance.id}/steps",
            cancel: "/sop/#{@instance.process_name}/#{@instance.id}/cancel"
          }
        }

        if @include_steps
          payload[:steps] = @instance.steps.order(:position).map do |step|
            StepSerializer.new(step, instance: @instance).as_json
          end
        end

        payload
      end
    end
  end
end
