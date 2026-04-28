module Ui
  # Base controller for the admin UI (Dashboard, Process Library, Instance
  # Dashboard, Process Detail, Instance Detail).
  #
  # Optional HTTP Basic auth is gated by ENV:
  #
  #   OPENSOP_UI_USER     — username expected on all /ui pages
  #   OPENSOP_UI_PASSWORD — password expected on all /ui pages
  #
  # If either variable is unset, auth is skipped (so local development and
  # the test suite work without ceremony). If both are set, every UI request
  # is challenged with HTTP Basic — failure returns 401 with a `realm=OpenSOP`
  # prompt.
  #
  # Production deployments SHOULD set both. Track GAP-9 for lifting this to
  # a proper session-based login once the engine supports multi-user admin.
  #
  # Note: /sop/* API endpoints use `X-SOP-Token` instead (see
  # Sop::ApplicationController). The two auth schemes coexist so API callers
  # and humans can use the same deployment without interference.
  class ApplicationController < ActionController::Base
    layout "application"

    before_action :authenticate_admin_ui!

    rescue_from ActiveRecord::RecordNotFound do |ex|
      render plain: "Not found: #{ex.message}", status: :not_found
    end

    rescue_from Opensop::InstanceExecutor::InvalidInputs,
                Opensop::InstanceExecutor::InvalidTransition,
                Opensop::DefinitionParser::InvalidDefinition,
                Opensop::InputResolver::UnresolvedReference do |ex|
      redirect_back fallback_location: "/", alert: ex.message
    end

    # When the views specialist hasn't shipped templates yet, render a
    # lightweight placeholder so routes are still verifiable. Rails 8's
    # ImplicitRender emits `head :no_content` (204) when no template is
    # found, which hides routing/controller issues behind empty bodies.
    # We check for the template up front and substitute a helpful 200 if
    # none exists. Once real templates ship, `super` renders them normally
    # and this override becomes a no-op.
    def default_render
      if lookup_context.exists?(action_name, [ self.class.controller_path ], false)
        super
      else
        render plain: "UI routes OK (views pending): #{controller_name}##{action_name}", status: :ok
      end
    end

    private

    def authenticate_admin_ui!
      expected_user = ENV["OPENSOP_UI_USER"].to_s
      expected_pass = ENV["OPENSOP_UI_PASSWORD"].to_s
      return if expected_user.empty? || expected_pass.empty?

      authenticate_or_request_with_http_basic("OpenSOP") do |u, p|
        ActiveSupport::SecurityUtils.secure_compare(u.to_s, expected_user) &&
          ActiveSupport::SecurityUtils.secure_compare(p.to_s, expected_pass)
      end
    end
  end
end
