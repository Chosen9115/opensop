module Ui
  # POST /instances/:id/steps/:step_id/submit — advances a step from the UI.
  # Accepts Rails form params with `outputs[...]` nested values.
  class StepsController < ApplicationController
    def submit
      instance = Sop::Instance.find(params[:instance_id])
      step = instance.steps.find_by!(step_id: params[:step_id])

      unless step.active? || step.failed?
        redirect_to ui_instance_path(instance),
                    alert: "Step #{step.step_id} is not awaiting submission (state=#{step.state})"
        return
      end

      outputs = params_hash(:outputs)
      decided_by = params[:decided_by].presence || "human:ui"

      Opensop::InstanceExecutor.submit_step(
        instance: instance,
        step_id: step.step_id,
        outputs: outputs,
        decided_by: decided_by
      )

      redirect_to ui_instance_path(instance), notice: "Step #{step.step_id} submitted"
    rescue Opensop::InstanceExecutor::InvalidInputs,
           Opensop::InstanceExecutor::InvalidTransition => e
      redirect_to ui_instance_path(instance), alert: e.message
    end

    private

    def params_hash(key)
      raw = params[key]
      return {} if raw.blank?
      if raw.respond_to?(:to_unsafe_h)
        raw.to_unsafe_h.deep_stringify_keys
      elsif raw.is_a?(Hash)
        raw.deep_stringify_keys
      else
        {}
      end
    end
  end
end
