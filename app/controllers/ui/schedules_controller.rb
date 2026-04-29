module Ui
  # GET /schedule — cron-driven recurring instance schedules.
  #
  # Lists every `Sop::Schedule` (enabled first, then by next run), summarised
  # into three hero tiles: active count, due-now count, and 24h failure count.
  #
  # The controller stays defensive: if the underlying table hasn't been
  # migrated yet (engine-only deployments, fresh setups), it renders the
  # "unavailable" empty state instead of erroring out — matching the
  # behaviour of the other Tier 1/2 informational pages.
  class SchedulesController < ApplicationController
    def index
      @schedules = safe_load_schedules
      @table_unavailable = @schedules.nil?
      @schedules ||= []
      @totals = compute_totals(@schedules)
    end

    private

    def safe_load_schedules
      Sop::Schedule.order(enabled: :desc, next_run_at: :asc, name: :asc).to_a
    rescue ActiveRecord::StatementInvalid
      nil
    end

    def compute_totals(schedules)
      now = Time.current
      cutoff = now - 24.hours
      {
        active: schedules.count(&:enabled?),
        due_now: schedules.count { |s| s.enabled? && s.next_run_at.present? && s.next_run_at <= now },
        failures_24h: schedules.count { |s| s.last_status == "failed" && s.last_run_at.present? && s.last_run_at >= cutoff }
      }
    end
  end
end
