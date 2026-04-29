# frozen_string_literal: true

module Opensop
  # Dispatches all currently-due `Sop::Schedule` rows by starting an instance
  # for each one via `Opensop::InstanceExecutor.start`. Updates the schedule
  # row to record the run and recompute the next-run timestamp.
  #
  # Returns a Result struct shaped for the caller (admin UI / cron job logger):
  #
  #   Result(dispatched_count:, skipped_count:, failures:)
  #
  # `failures` is an array of `Failure(schedule_id:, reason:)` structs.
  #
  # The whole pass is wrapped so that a missing `sop_schedules` table — i.e.
  # an unmigrated environment — returns an empty result instead of raising,
  # mirroring the posture used by `Opensop::MetricsRollup` / `CostRollup`.
  module ScheduleDispatcher
    Result = Struct.new(:dispatched_count, :skipped_count, :failures, keyword_init: true)
    Failure = Struct.new(:schedule_id, :reason, keyword_init: true)

    module_function

    def call(now: Time.current)
      schedules = Sop::Schedule.due.to_a
      dispatched = 0
      skipped = 0
      failures = []

      schedules.each do |schedule|
        begin
          process = Sop::Process
                      .where(name: schedule.process_name)
                      .published
                      .order(version: :desc)
                      .first

          if process.nil?
            mark_failed!(schedule, now, "process_not_found")
            failures << Failure.new(schedule_id: schedule.id, reason: "process_not_found")
            skipped += 1
            next
          end

          instance = Opensop::InstanceExecutor.start(
            process: process,
            inputs: schedule.inputs.to_h,
            metadata: { source: "schedule", schedule_id: schedule.id }
          )

          schedule.update!(
            last_run_at: now,
            last_instance_id: instance.id,
            last_status: "success",
            failure_count: 0,
            next_run_at: schedule.compute_next_run_at(from: now)
          )
          dispatched += 1
        rescue StandardError => e
          Rails.logger.warn("[Opensop::ScheduleDispatcher] schedule=#{schedule.id} failed: #{e.class}: #{e.message}")
          mark_failed!(schedule, now, "#{e.class}: #{e.message}")
          failures << Failure.new(schedule_id: schedule.id, reason: e.message.to_s.first(200))
        end
      end

      Result.new(dispatched_count: dispatched, skipped_count: skipped, failures: failures)
    rescue ActiveRecord::StatementInvalid
      # Table not yet migrated — return empty result (graceful for unmigrated envs).
      Result.new(dispatched_count: 0, skipped_count: 0, failures: [])
    end

    def mark_failed!(schedule, now, _reason)
      schedule.update!(
        last_run_at: now,
        last_status: "failed",
        failure_count: schedule.failure_count.to_i + 1,
        next_run_at: schedule.compute_next_run_at(from: now)
      )
    rescue StandardError => e
      Rails.logger.warn("[Opensop::ScheduleDispatcher] could not mark schedule=#{schedule.id} failed: #{e.class}: #{e.message}")
    end
  end
end
