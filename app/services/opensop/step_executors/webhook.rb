# frozen_string_literal: true

module Opensop
  module StepExecutors
    # Webhook step — for MVP we do NOT make an outbound HTTP call.
    # Instead we provision a Sop::Callback row the inbound webhook
    # endpoint will look up, and pause the instance.
    class Webhook
      def call(step, instance, definition)
        webhook = definition["webhook"] || {}
        response_mode = webhook["response_mode"] || "callback"

        callback = instance.callbacks.create!(
          step_id: step.step_id,
          status: "pending",
          response: {},
          expires_at: parse_timeout(webhook["poll_timeout"])
        )

        instance.events.create!(
          step_id: step.step_id,
          event_type: "step.webhook_registered",
          actor: "system",
          data: {
            response_mode: response_mode,
            callback_path: callback.callback_path,
            method: webhook["method"],
            url: webhook["url"]
          }
        )

        { waiting: "waiting_for_callback" }
      end

      private

      def parse_timeout(value)
        return nil if value.blank?
        seconds = duration_to_seconds(value.to_s)
        seconds ? seconds.seconds.from_now : nil
      end

      def duration_to_seconds(str)
        if (m = str.match(/\A(\d+)\s*([smhdwMy])\z/))
          unit = { "s" => 1, "m" => 60, "h" => 3600, "d" => 86_400,
                   "w" => 604_800, "M" => 2_592_000, "y" => 31_536_000 }[m[2]]
          m[1].to_i * unit
        end
      end
    end
  end
end
