module Ui
  # frozen_string_literal: true

  # GET  /instances          — list instances (filter by state/process)
  # GET  /instances/:id      — detail view with steps
  # POST /instances/:id/cancel — cancel an instance
  class InstancesController < ApplicationController
    DEFAULT_LIMIT = 50

    def index
      scope = Sop::Instance.order(created_at: :desc)
      scope = scope.where(state: params[:state]) if params[:state].present?
      scope = scope.where(process_name: params[:process]) if params[:process].present?

      @state_filter = params[:state]
      @process_filter = params[:process]
      @total = scope.count
      @instances = scope.limit(DEFAULT_LIMIT)
      @process_names = Sop::Process.distinct.order(:name).pluck(:name)
    end

    def show
      @instance = Sop::Instance.find(params[:id])
      @steps = @instance.steps.order(:position)
      @events = @instance.events.order(created_at: :asc).limit(50)
      @process = Sop::Process.find_by(name: @instance.process_name, version: @instance.process_version)

      # Build debug prompts for any error surfaces on this page so the view can
      # render copy-to-clipboard buttons. Nil/empty when there's no error.
      @instance_debug_prompt =
        if @instance.error.present?
          Opensop::DebugPromptBuilder.new(instance: @instance).call
        end

      @step_debug_prompts = @steps.each_with_object({}) do |step, acc|
        next unless step.error.present?
        acc[step.id] = Opensop::DebugPromptBuilder.new(instance: @instance, step: step).call
      end
    end

    def cancel
      instance = Sop::Instance.find(params[:id])
      reason = params[:reason].presence || "cancelled via UI"
      Opensop::InstanceExecutor.cancel!(instance, reason: reason)
      redirect_to ui_instance_path(instance), notice: "Instance cancelled"
    end
  end
end
