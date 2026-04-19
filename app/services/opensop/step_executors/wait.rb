# frozen_string_literal: true

module Opensop
  module StepExecutors
    # Wait step.
    # - If the definition has `wait.seconds`, this returns immediately with
    #   `waited: true` (we don't actually sleep — MVP synchronous stub).
    # - If the definition has `wait.until`, we pause waiting for a condition.
    class Wait
      def call(step, _instance, definition)
        wait_block = definition["wait"] || {}
        if wait_block.key?("seconds")
          { outputs: { "waited" => true, "seconds" => wait_block["seconds"] } }
        elsif wait_block.key?("until")
          { waiting: "waiting_for_callback" }
        else
          { outputs: { "waited" => true } }
        end
      end
    end
  end
end
