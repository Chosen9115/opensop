# frozen_string_literal: true

module Opensop
  module StepExecutors
    # Form steps pause the instance until `submit_step` is called externally
    # (e.g. via `POST /sop/:name/:id/steps/:step_id/submit`).
    class Form
      def call(_step, _instance, _definition)
        { waiting: "waiting_for_input" }
      end
    end
  end
end
