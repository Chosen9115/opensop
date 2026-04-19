module Ui
  # GET / — high-level dashboard with instance-state counts and a
  # list of the most recent instances.
  class DashboardController < ApplicationController
    WAITING_SUB_STATES = %w[waiting_for_input waiting_for_callback waiting_for_approval escalated].freeze

    def index
      @stats = {
        running: Sop::Instance.where(state: "running").count,
        waiting: Sop::Instance
          .joins(:steps)
          .where(sop_steps: { sub_state: WAITING_SUB_STATES })
          .distinct
          .count,
        completed: Sop::Instance.where(state: "completed").count,
        failed: Sop::Instance.where(state: "failed").count
      }
      @recent_instances = Sop::Instance.order(created_at: :desc).limit(10)
      @process_count = Sop::Process.published.count
    end
  end
end
