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
    before_action :load_rail_events

    helper_method :sidebar_counts, :api_token_active?, :show_rail?, :cmdk_dataset

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

    # Whether to render the right-hand activity rail in the layout. Subclasses
    # can override to return false on focus-mode pages.
    def show_rail?
      true
    end

    private

    # Populate @rail_events with the 12 most recent Sop::Event records for the
    # right-hand activity rail. Wrapped in StatementInvalid rescue so the
    # layout still renders before the events table has been migrated.
    def load_rail_events
      @rail_events = begin
        Sop::Event.includes(:instance).order(created_at: :desc).limit(12).to_a
      rescue ActiveRecord::StatementInvalid
        []
      end
    end

    # Counts shown in the sidebar nav. Memoized per-request. Wrapped in
    # StatementInvalid rescue for the same reason as load_rail_events.
    def sidebar_counts
      @_sidebar_counts ||= begin
        {
          processes: Sop::Process.published.count,
          instances_running: Sop::Instance.where(state: "running").count,
          instances_waiting: Sop::Instance
            .joins(:steps)
            .where(sop_steps: { sub_state: %w[waiting_for_input waiting_for_callback waiting_for_approval escalated] })
            .distinct
            .count
        }
      rescue ActiveRecord::StatementInvalid
        { processes: 0, instances_running: 0, instances_waiting: 0 }
      end
    end

    # True when an outbound API token is configured. Drives the "API token
    # active" status pill in the sidebar.
    def api_token_active?
      ENV["OPENSOP_API_TOKEN"].to_s.strip != ""
    end

    # Dataset for the ⌘K command palette. Combines static nav entries with the
    # current set of published processes and the most recent instances so the
    # user can jump anywhere with a few keystrokes. Wrapped in
    # StatementInvalid rescue so the layout still renders before the relevant
    # tables have been migrated.
    def cmdk_dataset
      @_cmdk_dataset ||= begin
        nav = [
          { label: I18n.t("opensop.nav.dashboard", default: "Dashboard"),
            kind: "Navigate", href: ui_dashboard_path },
          { label: I18n.t("opensop.nav.processes", default: "Processes"),
            kind: "Navigate", href: ui_processes_path },
          { label: I18n.t("opensop.nav.instances", default: "Instances"),
            kind: "Navigate", href: ui_instances_path }
        ]
        processes = Sop::Process.published.order(:name).pluck(:name).map do |n|
          { label: n, kind: "Process", href: ui_process_path(name: n) }
        end
        instances = Sop::Instance.order(created_at: :desc).limit(20).pluck(:id).map do |id|
          { label: id.to_s.first(8), kind: "Instance", href: ui_instance_path(id) }
        end
        nav + processes + instances
      rescue ActiveRecord::StatementInvalid
        []
      end
    end

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
