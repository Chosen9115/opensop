# frozen_string_literal: true

module Opensop
  # ActiveJob wrapper around `Opensop::ScheduleDispatcher.call`.
  # Intended to be invoked on a fixed cadence (e.g. every minute) by the
  # host's cron / scheduler so that any schedules whose `next_run_at` has
  # come due get dispatched to the engine.
  class ScheduleDispatchJob < ApplicationJob
    queue_as :default

    def perform
      result = Opensop::ScheduleDispatcher.call
      Rails.logger.info(
        "[Opensop::ScheduleDispatchJob] dispatched=#{result.dispatched_count} " \
        "skipped=#{result.skipped_count} failures=#{result.failures.size}"
      )
      result
    end
  end
end
