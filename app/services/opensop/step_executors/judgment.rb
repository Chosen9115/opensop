# frozen_string_literal: true

module Opensop
  module StepExecutors
    # Judgment steps route to an LLM or human. Until the LLM router is
    # wired up, every judgment step escalates to a human.
    class Judgment
      def call(step, instance, _definition)
        instance.events.create!(
          step_id: step.step_id,
          event_type: "step.escalated",
          actor: "system",
          data: { reason: "llm_router_not_implemented" }
        )
        { waiting: "escalated" }
      end
    end
  end
end
