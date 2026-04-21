module Sop
  # POST /sop/triggers/:process_name
  #
  # Inbound trigger endpoint for third-party webhooks. A process declares
  # its trigger config in YAML under `process.trigger`:
  #
  #   trigger:
  #     type: webhook
  #     auth:
  #       scheme: hmac-sha256
  #       secret_env: CAL_WEBHOOK_SECRET
  #       header: X-Cal-Signature-256
  #       encoding: hex
  #       prefix: "sha256="
  #     input_mapping:
  #       attendee_email: "${payload.attendees.0.email}"
  #       source: "cal.com"
  #
  # Unlike `/sop/:name/start`, this endpoint does NOT require the
  # `X-SOP-Token` header — the HMAC signature IS the auth. This lets
  # third-party tools (Cal.com, Stripe, Typeform, HubSpot) post directly
  # without needing a host-side adapter to inject a bearer token.
  class TriggersController < ApplicationController
    skip_before_action :authenticate_sop_token!

    rescue_from ActionDispatch::Http::Parameters::ParseError do |ex|
      Rails.logger.warn("[Sop::TriggersController] malformed JSON: #{ex.message}")
      render json: { error: "invalid_payload", message: "body must be valid JSON" },
             status: :bad_request
    end

    def receive
      process = Sop::Process.published.where(name: params[:process_name]).to_a.max_by { |p| version_key(p.version) }

      unless process
        render json: { error: "not_found", message: "process #{params[:process_name].inspect} not found" },
               status: :not_found
        return
      end

      trigger = (process.definition || {}).dig("process", "trigger") || {}
      unless trigger["type"].to_s == "webhook"
        render json: {
          error: "trigger_not_configured",
          message: "process #{process.name.inspect} does not declare a webhook trigger"
        }, status: :not_found
        return
      end

      raw_body = request.raw_post.to_s

      begin
        Opensop::WebhookAuth.verify!(
          config: trigger["auth"] || {},
          headers: request.headers,
          body: raw_body
        )
      rescue Opensop::WebhookAuth::InvalidSignature => e
        Rails.logger.warn("[Sop::TriggersController] rejected #{process.name}: #{e.message}")
        render json: { error: "invalid_signature", message: e.message }, status: :unauthorized
        return
      rescue Opensop::WebhookAuth::MisconfiguredAuth => e
        Rails.logger.error("[Sop::TriggersController] misconfigured #{process.name}: #{e.message}")
        render json: { error: "trigger_misconfigured", message: e.message }, status: :internal_server_error
        return
      end

      payload =
        begin
          raw_body.empty? ? {} : JSON.parse(raw_body)
        rescue JSON::ParserError => e
          Rails.logger.warn("[Sop::TriggersController] rejected #{process.name}: invalid JSON (#{e.message})")
          render json: { error: "invalid_payload", message: "body must be valid JSON" },
                 status: :bad_request
          return
        end

      mapping = trigger["input_mapping"] || {}
      inputs =
        begin
          resolve_inputs(mapping, payload)
        rescue Opensop::Templating::MissingVariable => e
          # Q2 option (C) — return 200 so the provider doesn't retry, but
          # log loudly so we can spot misconfigurations.
          Rails.logger.warn(
            "[Sop::TriggersController] MAPPING_REJECTED process=#{process.name} " \
            "reason=#{e.message} payload=#{raw_body}"
          )
          render json: { status: "accepted", action: "logged", reason: e.message }, status: :ok
          return
        end

      begin
        instance = Opensop::InstanceExecutor.start(
          process: process,
          inputs: inputs,
          metadata: { "source" => "trigger", "trigger_process" => process.name }
        )
      rescue Opensop::InstanceExecutor::InvalidInputs => e
        # Same as above — don't bounce the provider, log for ops.
        Rails.logger.warn(
          "[Sop::TriggersController] INSTANCE_REJECTED process=#{process.name} " \
          "reason=#{e.message} inputs=#{inputs.to_json}"
        )
        render json: { status: "accepted", action: "logged", reason: e.message }, status: :ok
        return
      end

      render json: {
        status: "started",
        instance_id: instance.id
      }, status: :ok
    end

    private

    def resolve_inputs(mapping, payload)
      mapping.each_with_object({}) do |(key, value), acc|
        acc[key.to_s] = Opensop::Templating.resolve_value(value, payload: payload)
      end
    end

    def version_key(version)
      Gem::Version.new(version.to_s)
    rescue ArgumentError
      Gem::Version.new("0")
    end
  end
end
