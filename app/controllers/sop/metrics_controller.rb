module Sop
  # GET /sop/metrics — JSON metrics rollup over the last 24h.
  #
  # Returns per-instance throughput totals, per-process breakdown, and a
  # current snapshot of step health. Auth is inherited from
  # Sop::ApplicationController (`X-SOP-Token`).
  class MetricsController < ApplicationController
    def index
      rollup = Opensop::MetricsRollup.call

      render json: {
        window_seconds: Opensop::MetricsRollup::WINDOW.to_i,
        totals: rollup.totals,
        per_process: rollup.per_process,
        step_health: rollup.step_health
      }
    end
  end
end
