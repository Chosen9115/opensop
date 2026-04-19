# frozen_string_literal: true

module Opensop
  module StepExecutors
    # Fire-and-forget notification stub. Returns immediately with
    # `notified: true` so the instance can advance.
    class Notification
      def call(_step, _instance, _definition)
        { outputs: { "notified" => true, "email_sent" => true } }
      end
    end
  end
end
