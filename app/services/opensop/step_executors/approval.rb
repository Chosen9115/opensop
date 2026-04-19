# frozen_string_literal: true

module Opensop
  module StepExecutors
    # Approval steps pause for a human decision. They advance when
    # `submit_step` is called with the approval outcome.
    class Approval
      def call(_step, _instance, _definition)
        { waiting: "waiting_for_approval" }
      end
    end
  end
end
