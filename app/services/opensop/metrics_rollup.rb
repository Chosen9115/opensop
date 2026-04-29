# frozen_string_literal: true

module Opensop
  # Aggregates Sop::Instance / Sop::Step counters for the admin Metrics page
  # and the corresponding `/sop/metrics` JSON endpoint.
  #
  # Returns a Result struct shaped for both surfaces:
  #
  #   {
  #     totals: {
  #       instances_started:, instances_completed:, instances_failed:,
  #       completion_rate:, avg_duration_seconds:, p95_duration_seconds:
  #     },
  #     per_process:  [ { process_name:, version:, started:, completed:, failed:, in_flight: }, ... ],
  #     step_health:  { pending:, active:, completed:, failed:, skipped: }
  #   }
  #
  # Window-bounded aggregations (totals + per_process) are scoped to the last
  # 24 hours by default. `step_health` is a current snapshot, not windowed.
  #
  # Aggregation queries are wrapped in `safe_aggregate` so the page renders
  # gracefully if the underlying tables have not yet been migrated — same
  # posture used by `Opensop::CostRollup` and `Ui::ApplicationController`.
  class MetricsRollup
    WINDOW = 24.hours
    PER_PROCESS_LIMIT = 20

    Result = Struct.new(:totals, :per_process, :step_health, keyword_init: true)

    def self.call(now: Time.current)
      new(now: now).call
    end

    def initialize(now: Time.current)
      @now = now
      @since = now - WINDOW
    end

    def call
      Result.new(
        totals: totals,
        per_process: per_process,
        step_health: step_health
      )
    end

    private

    attr_reader :now, :since

    def instance_window_scope
      Sop::Instance.where(created_at: since..now)
    end

    def totals
      started = safe_aggregate { instance_window_scope.count } || 0
      completed = safe_aggregate { instance_window_scope.where(state: "completed").count } || 0
      failed = safe_aggregate { instance_window_scope.where(state: "failed").count } || 0

      denom = completed + failed
      completion_rate = denom.positive? ? (completed.to_f / denom) : 0.0

      durations = safe_aggregate { completed_durations_in_window } || []

      {
        instances_started: started.to_i,
        instances_completed: completed.to_i,
        instances_failed: failed.to_i,
        completion_rate: completion_rate.to_f,
        avg_duration_seconds: average(durations),
        p95_duration_seconds: percentile(durations, 0.95)
      }
    end

    # Pulls completed-instance durations (in seconds) for the window. Falls
    # back to (updated_at - created_at) when `completed_at` is null on a
    # row marked completed (defensive — the executor sets it, but old rows
    # may not have it).
    def completed_durations_in_window
      instance_window_scope
        .where(state: "completed")
        .pluck(
          Arel.sql(
            "EXTRACT(EPOCH FROM (COALESCE(completed_at, updated_at) - created_at))"
          )
        )
        .map { |v| v.to_f }
        .reject { |v| v.negative? }
    end

    def average(durations)
      return 0.0 if durations.empty?

      (durations.sum.to_f / durations.size).round(2)
    end

    # Approx 95th percentile. We sort in Ruby to keep the implementation
    # database-agnostic (and because the result-set size here is bounded
    # by completed-instance count in a 24h window, which is small).
    def percentile(durations, pct)
      return 0.0 if durations.empty?

      sorted = durations.sort
      idx = (pct * sorted.size).floor
      idx = sorted.size - 1 if idx >= sorted.size
      idx = 0 if idx.negative?
      sorted[idx].to_f.round(2)
    end

    def per_process
      window_rows = safe_aggregate do
        instance_window_scope
          .group(:process_name, :process_version, :state)
          .count
      end || {}

      # in_flight is NOT windowed — current pending/running across all time
      # for each (name, version). Only useful for processes that also have
      # window activity, so we pull it in lazily.
      in_flight_rows = safe_aggregate do
        Sop::Instance
          .where(state: %w[pending running])
          .group(:process_name, :process_version)
          .count
      end || {}

      grouped = Hash.new { |h, k| h[k] = { started: 0, completed: 0, failed: 0, in_flight: 0 } }

      window_rows.each do |(name, version, state), count|
        key = [ name, version ]
        grouped[key][:started] += count.to_i
        case state
        when "completed" then grouped[key][:completed] += count.to_i
        when "failed"    then grouped[key][:failed]    += count.to_i
        end
      end

      in_flight_rows.each do |(name, version), count|
        key = [ name, version ]
        # Make sure we surface in_flight even if no window activity exists.
        grouped[key] # touch default
        grouped[key][:in_flight] = count.to_i
      end

      grouped
        .map do |(name, version), counts|
          {
            process_name: name.to_s,
            version: version.to_s,
            started: counts[:started].to_i,
            completed: counts[:completed].to_i,
            failed: counts[:failed].to_i,
            in_flight: counts[:in_flight].to_i
          }
        end
        .sort_by { |row| -row[:started] }
        .first(PER_PROCESS_LIMIT)
    end

    def step_health
      counts = safe_aggregate { Sop::Step.group(:state).count } || {}

      {
        pending: counts["pending"].to_i,
        active: counts["active"].to_i,
        completed: counts["completed"].to_i,
        failed: counts["failed"].to_i,
        skipped: counts["skipped"].to_i
      }
    end

    # Mirrors CostRollup#safe_aggregate: if the table is missing or the query
    # blows up, return nil so callers can substitute zeros instead of 500-ing
    # the whole page.
    def safe_aggregate
      yield
    rescue ActiveRecord::StatementInvalid
      nil
    end
  end
end
