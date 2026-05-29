# frozen_string_literal: true

module Demo
  # Nightly reset job for the public demo deployment.
  #
  # Runs on the schedule defined by `Opensop::DemoMode::RESET_SCHEDULE_CRON`
  # (configured in config/recurring.yml). Clears all process instances so the
  # demo always starts each day from a clean, seeded state.
  #
  # Behaviour:
  #   - No-op when DEMO_MODE is not enabled (safe to leave in recurring.yml
  #     on non-demo deployments — it just logs and exits).
  #   - In a single transaction: destroys all Sop::Instance rows (which
  #     cascades to Sop::Step, Sop::Event, and Sop::Callback via dependent:
  #     :destroy defined on Sop::Instance) and then calls Demo::SeedLoader.call
  #     to reload process definitions and re-verify the demo token.
  #   - Logs a one-liner with cleared/reseeded counts so the job appears in
  #     Solid Queue's finished-job log and the Rails structured log.
  class ResetJob < ApplicationJob
    queue_as :default

    def perform
      unless Opensop::DemoMode.enabled?
        Rails.logger.info("[demo-reset] skipped — DEMO_MODE not enabled")
        return
      end

      cleared = 0
      seed_result = nil

      ActiveRecord::Base.transaction do
        # Delete children in dependency order before removing instances.
        # Sop::Instance declares `dependent: :destroy` for steps, events, and
        # callbacks, but we use bulk deletes here for speed since this is a
        # full reset — referential safety is guaranteed by the explicit ordering.
        Sop::Callback.delete_all
        Sop::Event.delete_all
        Sop::Step.delete_all
        cleared = Sop::Instance.delete_all

        seed_result = Demo::SeedLoader.call
      end

      Rails.logger.info(
        "[demo-reset] cleared #{cleared} instances, " \
        "reseeded #{seed_result.processes_loaded} processes"
      )
    end
  end
end
