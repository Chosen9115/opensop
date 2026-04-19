# frozen_string_literal: true

module Opensop
  module StepExecutors
    # Subprocess step stub. For MVP, pauses the parent instance without
    # actually starting a child instance.
    class Subprocess
      def call(step, instance, _definition)
        instance.events.create!(
          step_id: step.step_id,
          event_type: "step.subprocess_pending",
          actor: "system",
          data: { reason: "subprocess_executor_not_implemented" }
        )
        { waiting: "waiting_for_callback" }
      end
    end
  end
end
