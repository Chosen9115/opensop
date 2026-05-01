# frozen_string_literal: true

module Ui
  # API Reference site — multi-page documentation for the public OpenSOP HTTP API.
  #
  # Uses a custom layout (api_docs) that has its own topbar + sidebar and does NOT
  # render the main app's SidebarComponent or ActivityRailComponent.
  #
  # Navigation structure is driven entirely by Ui::ApiDocs::Catalog.
  class ApiDocsController < ApplicationController
    layout "api_docs"

    # The API reference is intentionally PUBLIC — no admin auth challenge —
    # so the docs are linkable, scrapable, and indexable. Content is 100%
    # static (driven by Ui::ApiDocs::Catalog + i18n) so there is nothing
    # workspace-scoped to leak.
    skip_before_action :authenticate_admin_ui!

    helper_method :admin_authenticated?, :docs_cmdk_dataset

    # Defensive override — this layout doesn't render the standard rail, but guard
    # against any future layout changes that might check this.
    def show_rail?
      false
    end

    # GET /api-docs
    # Renders the Quickstart landing page.
    def index
    end

    # GET /api-docs/guides/:slug
    # 404 if the slug is not in the catalog.
    def guide
      @guide = Ui::ApiDocs::Catalog.guide(params[:slug])
      raise ActionController::RoutingError, "Guide not found: #{params[:slug]}" unless @guide
    end

    # GET /api-docs/endpoints/:slug
    # 404 if the slug is not in the catalog.
    def endpoint
      @endpoint = Ui::ApiDocs::Catalog.endpoint(params[:slug])
      raise ActionController::RoutingError, "Endpoint not found: #{params[:slug]}" unless @endpoint

      @section = Ui::ApiDocs::Catalog.section_for_endpoint(params[:slug])
    end

    private

    # True when the visitor has valid admin credentials (or admin auth is
    # disabled by missing env vars). Used to conditionally show admin-only
    # links such as the topbar Dashboard link on this otherwise-public page.
    # Does NOT challenge the visitor — read-only check.
    def admin_authenticated?
      expected_user = ENV["OPENSOP_UI_USER"].to_s
      expected_pass = ENV["OPENSOP_UI_PASSWORD"].to_s
      return true if expected_user.empty? || expected_pass.empty?

      result = authenticate_with_http_basic do |u, p|
        ActiveSupport::SecurityUtils.secure_compare(u.to_s, expected_user) &&
          ActiveSupport::SecurityUtils.secure_compare(p.to_s, expected_pass)
      end
      result == true
    end

    # Dataset for the ⌘K command palette modal. One row per guide and per
    # endpoint, ordered the same way the sidebar groups them. Each row carries
    # a kind ("doc" or HTTP verb), a label, the navigation href, and a meta
    # string shown on the right side of the row.
    def docs_cmdk_dataset
      guides = Ui::ApiDocs::Catalog::GUIDES.map do |guide|
        href = guide[:slug] == "quickstart" ? ui_api_docs_path : ui_api_docs_guide_path(guide[:slug])
        {
          kind:  "doc",
          label: I18n.t("opensop.api_docs.guides.#{guide[:slug].underscore}.label"),
          href:  href,
          meta:  I18n.t("opensop.api_docs.cmdk.section.getting_started")
        }
      end

      endpoints = Ui::ApiDocs::Catalog::ENDPOINT_SECTIONS.flat_map do |section|
        section[:endpoints].map do |ep|
          {
            kind:  ep[:method],
            label: ep[:path],
            href:  ui_api_docs_endpoint_path(ep[:slug]),
            meta:  I18n.t("opensop.api_docs.endpoints.#{ep[:slug].underscore}.title", default: ep[:slug].tr("-", " ").capitalize)
          }
        end
      end

      guides + endpoints
    end
  end
end
