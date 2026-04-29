module Ui
  # GET /costs — LLM cost rollup page.
  #
  # Surfaces a 30-day window of spend across all `Sop::LlmCall` records:
  #   * 4 hero tiles (total spend, call count, tokens in/out)
  #   * per-day bar chart
  #   * top 10 most expensive steps
  #
  # Aggregations live in `Opensop::CostRollup` so this controller stays
  # thin and the rollup logic is unit-testable in isolation.
  class CostsController < ApplicationController
    def index
      rollup = Opensop::CostRollup.call

      @totals = rollup.totals
      @daily = rollup.daily
      @top_steps = rollup.top_steps

      max = @daily.map { |d| d[:cost_cents] }.max.to_i
      @daily_max_cents = max.positive? ? max : 0
      @has_activity = @totals[:calls].positive?
    end
  end
end
