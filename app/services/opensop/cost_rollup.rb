# frozen_string_literal: true

module Opensop
  # Aggregates Sop::LlmCall data for the admin Costs page.
  #
  # Returns a hash shaped for the view:
  #
  #   {
  #     totals:    { spend_cents:, calls:, tokens_in:, tokens_out: },
  #     daily:     [ { date: Date, cost_cents: Integer }, ... ],  # last 30 entries
  #     top_steps: [ { step_name:, instance_id:, model:, cost_cents:, calls: }, ... ]
  #   }
  #
  # All aggregations are scoped to the last 30 days (`started_at >= 30.days.ago`).
  # Aggregation queries are wrapped so the page renders gracefully if the
  # underlying table has not been migrated yet — same posture used by
  # Ui::ApplicationController#sidebar_counts elsewhere in the app.
  class CostRollup
    WINDOW = 30.days
    TOP_STEPS_LIMIT = 10

    Result = Struct.new(:totals, :daily, :top_steps, keyword_init: true)

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
        daily: daily,
        top_steps: top_steps
      )
    end

    private

    attr_reader :now, :since

    def base_scope
      Sop::LlmCall.where(started_at: since..)
    end

    def totals
      row = safe_aggregate do
        base_scope.pick(
          Arel.sql("COALESCE(SUM(cost_cents), 0)"),
          Arel.sql("COUNT(*)"),
          Arel.sql("COALESCE(SUM(input_tokens), 0)"),
          Arel.sql("COALESCE(SUM(output_tokens), 0)")
        )
      end

      spend_cents, calls, tokens_in, tokens_out = row || [ 0, 0, 0, 0 ]

      {
        spend_cents: spend_cents.to_i,
        calls: calls.to_i,
        tokens_in: tokens_in.to_i,
        tokens_out: tokens_out.to_i
      }
    end

    # Returns one entry per day for the last 30 days (oldest -> newest),
    # zero-filled for days with no calls.
    def daily
      grouped = safe_aggregate do
        base_scope
          .group(Arel.sql("date_trunc('day', started_at)::date"))
          .sum(:cost_cents)
      end || {}

      # Normalise keys to Date (Postgres returns Date already, but be defensive).
      indexed = grouped.transform_keys do |key|
        key.is_a?(Date) ? key : Date.parse(key.to_s)
      end

      start_day = since.to_date
      end_day = now.to_date
      (start_day..end_day).map do |day|
        { date: day, cost_cents: indexed[day].to_i }
      end
    end

    def top_steps
      rows = safe_aggregate do
        base_scope
          .joins(:step)
          .group(:step_id, "sop_steps.step_name", "sop_steps.instance_id", :model)
          .order(Arel.sql("SUM(cost_cents) DESC NULLS LAST"))
          .limit(TOP_STEPS_LIMIT)
          .pluck(
            "sop_steps.step_name",
            "sop_steps.instance_id",
            :model,
            Arel.sql("COALESCE(SUM(cost_cents), 0) AS total_cost"),
            Arel.sql("COUNT(*) AS call_count")
          )
      end || []

      rows.map do |step_name, instance_id, model, total_cost, call_count|
        {
          step_name: step_name.to_s,
          instance_id: instance_id.to_s,
          model: model.to_s,
          cost_cents: total_cost.to_i,
          calls: call_count.to_i
        }
      end
    end

    # Mirrors the sidebar_counts posture: if the table is missing or the
    # query blows up, return nil so callers can fall back to zeros instead
    # of 500-ing the whole page.
    def safe_aggregate
      yield
    rescue ActiveRecord::StatementInvalid
      nil
    end
  end
end
