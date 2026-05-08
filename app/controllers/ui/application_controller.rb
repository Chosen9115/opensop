module Ui
  # Base controller for the admin UI (Dashboard, Process Library, Instance
  # Dashboard, Process Detail, Instance Detail).
  #
  # Auth contract (Phase 4 cutover — GAP-9 closed):
  #
  # Every /ui route requires a valid session cookie. Authentication is
  # session-based, backed by passkeys (with magic-link as the bootstrap
  # path). The `Authenticatable` concern reads the signed cookie named
  # `:opensop_session`, resolves it to an `AuthSession` row, and exposes
  # `current_user` / `signed_in?` to controllers and views. Unauthenticated
  # requests are redirected to `/auth/sign_in` with a `return_to` parameter.
  #
  # The previous HTTP Basic gate (OPENSOP_UI_USER / OPENSOP_UI_PASSWORD) has
  # been removed entirely. /sop/* API endpoints continue to use
  # `X-SOP-Token` (see Sop::ApplicationController) — that path is unchanged.
  class ApplicationController < ActionController::Base
    include Authenticatable

    layout "application"

    before_action :require_authentication
    before_action :load_rail_data

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

    # Populate the activity-rail data for all three tabs:
    # - @rail_events: last 12 Sop::Event rows (Feed)
    # - @rail_llm_calls: last 12 Sop::LlmCall rows (Agents)
    # - @rail_up_next: combined upcoming schedules + waiting steps (Up next)
    #
    # Each branch is wrapped in StatementInvalid so the layout still renders
    # before the underlying tables have been migrated.
    def load_rail_data
      @rail_events = begin
        Sop::Event.includes(:instance).order(created_at: :desc).limit(12).to_a
      rescue ActiveRecord::StatementInvalid
        []
      end

      @rail_llm_calls = begin
        Sop::LlmCall.includes(step: :instance).order(started_at: :desc).limit(12).to_a
      rescue ActiveRecord::StatementInvalid, NameError
        []
      end

      @rail_up_next = begin
        items = []

        # Upcoming schedules (next_run_at in the future or just past)
        begin
          Sop::Schedule.enabled
                       .where("next_run_at IS NOT NULL")
                       .order(next_run_at: :asc)
                       .limit(8)
                       .each do |s|
            items << {
              kind: :schedule,
              label: s.name.to_s,
              target: s.process_name.to_s,
              eta_at: s.next_run_at
            }
          end
        rescue ActiveRecord::StatementInvalid, NameError
          # Schedule table not yet migrated.
        end

        # Steps currently awaiting human or callback input
        Sop::Step.includes(:instance)
                 .where(sub_state: %w[waiting_for_input waiting_for_callback waiting_for_approval escalated])
                 .order(updated_at: :desc)
                 .limit(8)
                 .each do |step|
          items << {
            kind: :waiting_step,
            label: step.step_id.to_s,
            target: step.instance&.process_name.to_s,
            eta_at: step.updated_at
          }
        end

        # Order: schedules by next_run_at asc, waiting steps mixed in by
        # eta_at; we just sort by eta_at for a single timeline view.
        items.sort_by { |i| i[:eta_at] || Time.current }.first(12)
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
  end
end
