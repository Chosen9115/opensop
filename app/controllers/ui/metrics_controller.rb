module Ui
  # GET /metrics — process throughput rollup page.
  #
  # Surfaces a 24h window of instance throughput across all processes:
  #   * 4 hero tiles (started, completed, failed, completion rate)
  #   * duration card (avg + p95)
  #   * per-process throughput table
  #   * current step health row
  #
  # All aggregation lives in `Opensop::MetricsRollup` so this controller
  # stays thin and the rollup is unit-testable in isolation.
  class MetricsController < ApplicationController
    def index
      rollup = Opensop::MetricsRollup.call

      @window_seconds = Opensop::MetricsRollup::WINDOW.to_i
      @totals = rollup.totals
      @per_process = rollup.per_process
      @step_health = rollup.step_health
    end
  end
end
