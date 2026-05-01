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
  end
end
