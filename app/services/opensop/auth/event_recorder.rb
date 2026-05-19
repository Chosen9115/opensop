# frozen_string_literal: true

module Opensop
  module Auth
    # Tiny wrapper around AuthEvent.create so callers don't have to repeat
    # the request-introspection boilerplate. Failures are logged but never
    # raise — auth flows must not break because audit logging fails.
    class EventRecorder
      def self.call(kind:, user: nil, request: nil, metadata: {})
        AuthEvent.create!(
          user: user,
          kind: kind.to_s,
          ip_address: request&.remote_ip,
          user_agent: request&.user_agent.to_s.first(255),
          metadata: metadata
        )
      rescue => e
        Rails.logger.warn("[Opensop::Auth::EventRecorder] failed to record #{kind}: #{e.class}: #{e.message}")
        nil
      end
    end
  end
end
