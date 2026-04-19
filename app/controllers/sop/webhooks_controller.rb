module Sop
  # POST /sop/webhooks/:callback_id
  #
  # Receives webhook callbacks from third parties (e.g. compliance
  # providers). Looks up the pending Sop::Callback, records the
  # response, writes it onto the step's outputs, completes the step,
  # and advances the instance.
  #
  # NOTE: This endpoint is called by third parties and therefore cannot
  # require an `X-SOP-Token`. Auth is skipped here.
  class WebhooksController < ApplicationController
    skip_before_action :authenticate_sop_token!

    def receive
      callback_path = "/sop/webhooks/#{params[:callback_id]}"
      callback = Sop::Callback.find_by(callback_path: callback_path)

      unless callback
        render json: { error: "not_found", message: "no pending callback at #{callback_path}" },
               status: :not_found
        return
      end

      if callback.received? || callback.expired?
        render json: { error: "callback_already_resolved", status: callback.status },
               status: :conflict
        return
      end

      payload = extract_payload

      # Persist the raw payload on the Sop::Callback row FIRST so that no
      # data is lost even if downstream validation rejects the payload.
      ActiveRecord::Base.transaction do
        callback.update!(response: payload, status: "received")
      end

      instance = callback.instance
      step = instance.steps.find_by(step_id: callback.step_id)

      if step
        base_outputs = step.outputs || {}
        new_outputs =
          if payload.is_a?(Hash)
            # Third parties typically POST top-level keys that match the
            # declared step outputs (e.g. {entity_id: "x", compliance_status: "approved"}).
            # Merge them at the top level so validate_outputs! is satisfied.
            base_outputs.merge(payload.deep_stringify_keys)
          else
            # Fall back to wrapping non-hash payloads (scalars, arrays, nil)
            # under "webhook_response" so the controller never crashes on odd input.
            base_outputs.merge("webhook_response" => payload)
          end

        begin
          Opensop::InstanceExecutor.submit_step(
            instance: instance,
            step_id: step.step_id,
            outputs: new_outputs,
            decided_by: "webhook"
          )
        rescue Opensop::InstanceExecutor::InvalidInputs => e
          # Callback row is already persisted with raw payload above, so no
          # data loss. Return a 422 indicating the payload did not satisfy
          # the declared step outputs.
          render json: {
            error: "invalid_callback_payload",
            message: e.message
          }, status: :unprocessable_entity
          return
        end
      end

      render json: { status: "received" }, status: :ok
    end

    private

    def extract_payload
      params_hash = request.request_parameters
      if params_hash.present?
        if params_hash.respond_to?(:to_unsafe_h)
          params_hash.to_unsafe_h
        else
          params_hash.to_h
        end
      else
        body = request.raw_post.to_s
        return {} if body.empty?
        begin
          JSON.parse(body)
        rescue JSON::ParserError
          { "raw" => body }
        end
      end
    end
  end
end
