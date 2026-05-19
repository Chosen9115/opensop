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

    helper_method :admin_authenticated?, :docs_cmdk_dataset, :docs_etag_for, :docs_lastmod

    # Cacheable, content-addressable etag for any docs response. The
    # underlying inputs (catalog + i18n + view templates) only change when
    # we deploy, so we tag every response with the current commit SHA and
    # the slug + format the request is asking for. Agents that re-fetch
    # against this etag get a 304.
    # Production: bound to the deploy revision — stable for the life of a
    # release, bumps when we redeploy.
    # Non-production: fingerprints the docs source files (catalog +
    # locale + every .md.erb partial) by mtime, so a local YAML or
    # partial edit busts the etag without needing a server restart.
    def docs_revision
      @_docs_revision ||=
        if Rails.env.production?
          ENV["OPENSOP_REVISION"].presence ||
            ENV["FLY_MACHINE_VERSION"].presence ||
            (defined?(Opensop::VERSION) ? Opensop::VERSION : "dev")
        else
          dev_template_fingerprint
        end
    end

    def docs_etag_for(*parts)
      [ docs_revision, *parts ].compact.join("-")
    end

    DEV_FINGERPRINT_GLOBS = %w[
      app/views/ui/api_docs/**/*.md.erb
      app/views/ui/api_docs/**/*.html.erb
      app/services/ui/api_docs/**/*.rb
      config/locales/opensop.en.yml
    ].freeze

    def dev_template_fingerprint
      Digest::MD5.hexdigest(
        dev_source_paths.map { |p| "#{p}:#{File.mtime(p).to_i}" }.join("|")
      )[0, 12]
    end

    def dev_source_paths
      @_dev_source_paths ||= DEV_FINGERPRINT_GLOBS.flat_map { |g| Dir[Rails.root.join(g)] }.sort
    end

    # Single timestamp used as <lastmod> for every URL in the sitemap. In
    # production this resolves to today's UTC date — sufficient for sitemap
    # consumers, which mostly care about day-level freshness. In dev we use
    # the most recent source-file mtime so a local edit immediately surfaces
    # in the sitemap output.
    def docs_lastmod
      @_docs_lastmod ||= begin
        if Rails.env.production?
          Date.current.iso8601
        else
          Time.at(dev_source_paths.map { |p| File.mtime(p).to_i }.max).utc.to_date.iso8601
        end
      end
    end

    # Defensive override — this layout doesn't render the standard rail, but guard
    # against any future layout changes that might check this.
    def show_rail?
      false
    end

    # GET /api-docs
    # Renders the Quickstart landing page (HTML only).
    def index
    end

    # GET /api-docs/guides/:slug      → HTML
    # GET /api-docs/guides/:slug.md   → markdown
    # 404 if the slug is not in the catalog.
    def guide
      @guide = Ui::ApiDocs::Catalog.guide(params[:slug])
      raise ActionController::RoutingError, "Guide not found: #{params[:slug]}" unless @guide

      respond_to do |format|
        format.html { fresh_when etag: docs_etag_for(:guide, @guide[:slug], :html), public: true }
        format.md do
          fresh_when etag: docs_etag_for(:guide, @guide[:slug], :md), public: true
          render layout: false, content_type: "text/markdown; charset=utf-8" unless performed?
        end
      end
    end

    # GET /api-docs/endpoints/:slug      → HTML
    # GET /api-docs/endpoints/:slug.md   → markdown
    # 404 if the slug is not in the catalog.
    def endpoint
      @endpoint = Ui::ApiDocs::Catalog.endpoint(params[:slug])
      raise ActionController::RoutingError, "Endpoint not found: #{params[:slug]}" unless @endpoint

      @section = Ui::ApiDocs::Catalog.section_for_endpoint(params[:slug])

      respond_to do |format|
        format.html { fresh_when etag: docs_etag_for(:endpoint, @endpoint[:slug], :html), public: true }
        format.md do
          fresh_when etag: docs_etag_for(:endpoint, @endpoint[:slug], :md), public: true
          render layout: false, content_type: "text/markdown; charset=utf-8" unless performed?
        end
      end
    end

    # GET /api-docs.md
    # Bundled markdown — every guide and endpoint concatenated, with a
    # table-of-contents block at the top. Designed to be fetched by an
    # agent in a single request.
    def bundled
      fresh_when etag: docs_etag_for(:bundled, :md), public: true
      render layout: false, content_type: "text/markdown; charset=utf-8" unless performed?
    end

    # GET /llms.txt
    # llms.txt convention — a small index file pointing AI crawlers at the
    # full markdown bundle and per-page markdown URLs.
    def llms_txt
      fresh_when etag: docs_etag_for(:llms_txt), public: true
      render layout: false, content_type: "text/plain; charset=utf-8" unless performed?
    end

    # GET /sitemap.xml
    # XML sitemap listing every HTML doc URL, each with an xhtml:link
    # alternate pointing at the .md sibling. Crawlers (Googlebot, ClaudeBot,
    # GPTBot, PerplexityBot, …) discover both formats in one fetch.
    def sitemap
      fresh_when etag: docs_etag_for(:sitemap), public: true
      render layout: false, content_type: "application/xml; charset=utf-8" unless performed?
    end

    private

    # True when the visitor's request carries valid admin credentials. Mirrors
    # the auth contract in Ui::ApplicationController#authenticate_admin_ui!.
    # When OPENSOP_UI_USER / OPENSOP_UI_PASSWORD are set the request is checked
    # against them in every env; when unset, the test env treats the visitor
    # as authenticated and dev / staging falls back to the 'admin' / 'admin'
    # development default. Used to conditionally show admin-only links (e.g.
    # the topbar Dashboard link) on this otherwise-public page. Does NOT
    # challenge the visitor — read-only check.
    def admin_authenticated?
      expected_user = ENV["OPENSOP_UI_USER"].presence
      expected_pass = ENV["OPENSOP_UI_PASSWORD"].presence

      if expected_user.nil? || expected_pass.nil?
        return true  if Rails.env.test?
        return false if Rails.env.production?
        expected_user = "admin"
        expected_pass = "admin"
      end

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
