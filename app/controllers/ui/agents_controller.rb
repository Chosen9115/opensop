module Ui
  # GET /agents — per-model LLM agent rollup page.
  #
  # Surfaces a 30-day window of `Sop::LlmCall` activity grouped by model
  # ("gpt-4o", "claude-3-5-sonnet", etc.) so admins can see which agents are
  # doing the work, how reliably they succeed, and what they cost.
  #
  # Aggregations live in `Opensop::AgentRollup` so this controller stays
  # thin and the rollup logic is unit-testable in isolation.
  class AgentsController < ApplicationController
    def index
      rollup = Opensop::AgentRollup.call

      @agents = rollup.agents
      @totals = rollup.totals
      @has_activity = @agents.any?
    end
  end
end
