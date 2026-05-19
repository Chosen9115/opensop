# frozen_string_literal: true

module Opensop
  # Aggregates Sop::LlmCall data for the admin Agents page.
  #
  # An "agent" here is a per-model rollup of LLM activity over the last 30
  # days, keyed by `Sop::LlmCall#model` (e.g. "gpt-4o", "claude-3-5-sonnet").
  # The result lets the admin UI surface which models are doing the work,
  # how reliably they succeed, and what they cost.
  #
  # Returns a Result with:
  #
  #   agents: [
  #     {
  #       model: String,
  #       total_calls: Integer,
  #       succeeded: Integer,
  #       errored: Integer,         # combines `errored` + `schema_failed`
  #       success_rate: Float,      # 0.0..1.0
  #       cost_cents: Integer,
  #       tokens_in: Integer,
  #       tokens_out: Integer,
  #       avg_confidence: Float,    # avg of joined sop_steps.confidence; 0.0 if none
  #       last_used_at: Time
  #     },
  #     ...
  #   ]
  #   totals: { models_count:, total_calls:, total_cost_cents: }
  #
  # All aggregations are scoped to the last 30 days (`started_at >= 30.days.ago`).
  # Aggregation queries are wrapped so the page renders gracefully if the
  # underlying table has not been migrated yet — same posture used by
  # Opensop::CostRollup elsewhere in the app.
  class AgentRollup
    WINDOW = 30.days

    Result = Struct.new(:agents, :totals, keyword_init: true)

    def self.call(now: Time.current)
      new(now: now).call
    end

    def initialize(now: Time.current)
      @now = now
      @since = now - WINDOW
    end

    def call
      list = agents
      Result.new(
        agents: list,
        totals: {
          models_count: list.size,
          total_calls: list.sum { |a| a[:total_calls] },
          total_cost_cents: list.sum { |a| a[:cost_cents] }
        }
      )
    end

    private

    attr_reader :now, :since

    def base_scope
      Sop::LlmCall.where(started_at: since..)
    end

    def agents
      rows = safe_aggregate do
        base_scope
          .group(:model)
          .order(Arel.sql("COUNT(*) DESC NULLS LAST"))
          .pluck(
            :model,
            Arel.sql("COUNT(*) AS total_calls"),
            Arel.sql("SUM(CASE WHEN status = 'succeeded' THEN 1 ELSE 0 END) AS succeeded"),
            Arel.sql("SUM(CASE WHEN status IN ('errored', 'schema_failed') THEN 1 ELSE 0 END) AS errored"),
            Arel.sql("COALESCE(SUM(cost_cents), 0) AS cost_cents"),
            Arel.sql("COALESCE(SUM(input_tokens), 0) AS tokens_in"),
            Arel.sql("COALESCE(SUM(output_tokens), 0) AS tokens_out"),
            Arel.sql("MAX(started_at) AS last_used_at")
          )
      end || []

      confidence_by_model = avg_confidence_by_model

      rows.map do |model, total_calls, succeeded, errored, cost_cents, tokens_in, tokens_out, last_used_at|
        total = total_calls.to_i
        success = succeeded.to_i
        rate = total.positive? ? (success.to_f / total) : 0.0

        {
          model: model.to_s,
          total_calls: total,
          succeeded: success,
          errored: errored.to_i,
          success_rate: rate,
          cost_cents: cost_cents.to_i,
          tokens_in: tokens_in.to_i,
          tokens_out: tokens_out.to_i,
          avg_confidence: confidence_by_model[model.to_s].to_f,
          last_used_at: last_used_at
        }
      end
    end

    # Returns { model => avg_confidence_float } for steps that the in-window
    # llm_calls were attached to, restricted to steps with non-null confidence.
    def avg_confidence_by_model
      rows = safe_aggregate do
        base_scope
          .joins(:step)
          .where.not(sop_steps: { confidence: nil })
          .group(:model)
          .pluck(
            :model,
            Arel.sql("AVG(sop_steps.confidence) AS avg_confidence")
          )
      end || []

      rows.each_with_object({}) do |(model, avg), acc|
        acc[model.to_s] = avg.to_f
      end
    end

    # Mirrors the CostRollup posture: if the table is missing or the query
    # blows up, return nil so callers can fall back to empty results instead
    # of 500-ing the whole page.
    def safe_aggregate
      yield
    rescue ActiveRecord::StatementInvalid
      nil
    end
  end
end
