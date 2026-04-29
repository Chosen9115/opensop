module Sop
  # Handles step inspection and submission:
  #   GET  /sop/steps/pending                     list steps waiting for an external worker
  #   GET  /sop/:name/:id/steps                   list steps
  #   POST /sop/:name/:id/steps/:step_id/submit   submit outputs, advance
  class StepsController < ApplicationController
    def pending
      steps = Sop::Step
                .active
                .where(sub_state: "waiting_for_worker")
                .eager_load(:instance)
                .order(:created_at)

      steps = steps.where(sop_instances: { process_name: params[:process_name] }) if params[:process_name].present?

      render json: {
        steps: steps.map { |step|
          {
            instance_id:  step.instance_id,
            process_name: step.instance.process_name,
            step_id:      step.step_id,
            step_name:    step.step_name,
            inputs:       step.inputs || {}
          }
        }
      }
    end

    def index
      instance = find_instance!
      steps = instance.steps.order(:position).map do |step|
        Sop::Serializers::StepSerializer.new(step, instance: instance).as_json
      end
      render json: { steps: steps }
    end

    def submit
      instance = find_instance!
      step = instance.steps.find_by!(step_id: params[:step_id])

      unless submittable?(step)
        render json: {
          error: "step_not_submittable",
          message: "step #{step.step_id.inspect} is not awaiting submission " \
                   "(state=#{step.state}, sub_state=#{step.sub_state})"
        }, status: :unprocessable_entity
        return
      end

      outputs = params_hash(:outputs)
      decided_by = params[:decided_by].presence || current_actor
      confidence = params[:confidence]

      Opensop::InstanceExecutor.submit_step(
        instance: instance,
        step_id: step.step_id,
        outputs: outputs,
        decided_by: decided_by,
        confidence: confidence
      )

      instance.reload
      step = instance.steps.find_by!(step_id: params[:step_id])

      render json: {
        step: Sop::Serializers::StepSerializer.new(step, instance: instance).as_json,
        instance: Sop::Serializers::InstanceSerializer.new(instance).as_json
      }
    end

    private

    def find_instance!
      Sop::Instance.where(process_name: params[:name]).find(params[:id])
    end

    def submittable?(step)
      step.active? || step.failed?
    end

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
