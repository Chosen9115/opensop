module Sop
  # Base controller for all /sop/* JSON API endpoints.
  #
  # Handles authentication via the `X-SOP-Token` header (optional in dev/test
  # when `OPENSOP_API_TOKEN` is unset) and translates domain errors into
  # structured JSON responses.
  class ApplicationController < ActionController::API
    @@unauth_warned = false

    before_action :authenticate_sop_token!

    rescue_from ActiveRecord::RecordNotFound do |ex|
      render json: { error: "not_found", message: ex.message }, status: :not_found
    end

    rescue_from Opensop::InstanceExecutor::InvalidInputs do |ex|
      render json: { error: "invalid_inputs", message: ex.message }, status: :unprocessable_entity
    end

    rescue_from Opensop::InstanceExecutor::InvalidTransition do |ex|
      render json: { error: "invalid_transition", message: ex.message }, status: :unprocessable_entity
    end

    rescue_from Opensop::DefinitionParser::InvalidDefinition do |ex|
      render json: { error: "invalid_definition", message: ex.message }, status: :unprocessable_entity
    end

    rescue_from Opensop::InputResolver::UnresolvedReference do |ex|
      render json: { error: "unresolved_reference", message: ex.message }, status: :unprocessable_entity
    end

    rescue_from Opensop::StepExecutor::UnknownType do |ex|
      render json: { error: "unknown_step_type", message: ex.message }, status: :unprocessable_entity
    end

    # Returns "agent" if the API token was presented, else "system".
    # Used as the default actor for event logging and step submissions.
    def current_actor
      @current_actor ||= presented_token.present? ? "agent" : "system"
    end

    private

    def authenticate_sop_token!
      expected = ENV["OPENSOP_API_TOKEN"]

      if expected.blank?
        unless @@unauth_warned
          Rails.logger.warn("[Sop::ApplicationController] OPENSOP_API_TOKEN not set — API is open (dev/test mode)")
          @@unauth_warned = true
        end
        return true
      end

      token = presented_token
      if token.blank? || !ActiveSupport::SecurityUtils.secure_compare(token.to_s, expected.to_s)
        render json: { error: "unauthorized" }, status: :unauthorized
        return false
      end

      true
    end

    def presented_token
      request.headers["X-SOP-Token"].presence
    end
  end
end
