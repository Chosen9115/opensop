module Sop
  module Serializers
    # Serializes a Sop::Step for API responses. Includes a `submit` link
    # pointing at the step submission endpoint so clients can navigate
    # without hard-coding URLs.
    class StepSerializer
      def initialize(step, instance: nil)
        @step = step
        @instance = instance || step.instance
      end

      def as_json(*)
        {
          id: @step.id,
          step_id: @step.step_id,
          name: @step.step_name,
          type: @step.step_type,
          state: @step.state,
          sub_state: @step.sub_state,
          inputs: @step.inputs || {},
          outputs: @step.outputs || {},
          decided_by: @step.decided_by,
          confidence: @step.confidence,
          position: @step.position,
          started_at: @step.started_at&.iso8601,
          completed_at: @step.completed_at&.iso8601,
          error: @step.error,
          links: {
            submit: "/sop/#{@instance.process_name}/#{@instance.id}/steps/#{@step.step_id}/submit"
          }
        }
      end
    end
  end
end
