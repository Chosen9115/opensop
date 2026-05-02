require "rails_helper"

# Covers GET /api-docs — a static reference page documenting the public
# OpenSOP HTTP API. The route itself is wired up by the integration agent
# in config/routes/ui.rb (`get "/api-docs", to: "ui/api_docs#index"`); until
# that lands, this spec will fail with an ActionController::RoutingError —
# that's expected and is the integration handoff signal.
RSpec.describe "Ui::ApiDocs", type: :request do
  before do
    ENV.delete("OPENSOP_UI_USER")
    ENV.delete("OPENSOP_UI_PASSWORD")
  end

  let(:endpoint_paths) do
    [
      "/sop/",
      "/sop/instances",
      "/sop/webhooks/:callback_id",
      "/sop/triggers/:process_name",
      "/sop/:name/schema",
      "/sop/:name/start",
      "/sop/:name/:id",
      "/sop/:name/:id/cancel",
      "/sop/:name/:id/steps",
      "/sop/:name/:id/steps/:step_id/submit"
    ]
  end

  it "returns 200 OK" do
    get "/api-docs"
    expect(response).to have_http_status(:ok)
  end

  it "renders the Quickstart page heading on the index" do
    get "/api-docs"
    expect(response.body).to include("Quickstart")
  end

  it "documents every public /sop/* endpoint path via the sidebar" do
    get "/api-docs"
    endpoint_paths.each do |path|
      expect(response.body).to include(path),
        "expected /api-docs body to include endpoint path #{path}"
    end
  end

  it "mentions the X-SOP-Token auth header" do
    get "/api-docs"
    expect(response.body).to include("X-SOP-Token")
  end

  context "guide pages" do
    Ui::ApiDocs::Catalog::GUIDES.each do |guide|
      it "returns 200 for /api-docs/guides/#{guide[:slug]}" do
        get "/api-docs/guides/#{guide[:slug]}"
        expect(response).to have_http_status(:ok)
      end
    end

    it "returns 404 for an unknown guide slug" do
      get "/api-docs/guides/nonexistent-guide"
      expect(response).to have_http_status(:not_found)
    end
  end

  context "endpoint pages" do
    Ui::ApiDocs::Catalog::ENDPOINT_SECTIONS.flat_map { |s| s[:endpoints] }.each do |ep|
      it "returns 200 for /api-docs/endpoints/#{ep[:slug]}" do
        get "/api-docs/endpoints/#{ep[:slug]}"
        expect(response).to have_http_status(:ok)
      end
    end

    it "returns 404 for an unknown endpoint slug" do
      get "/api-docs/endpoints/nonexistent-endpoint"
      expect(response).to have_http_status(:not_found)
    end
  end

  # The API reference is intentionally public so docs are linkable and
  # scrapable. Even when the rest of the admin UI is locked behind HTTP
  # Basic auth (OPENSOP_UI_USER / OPENSOP_UI_PASSWORD), /api-docs and its
  # sub-pages must NOT challenge the visitor.
  context "when admin HTTP Basic auth is configured" do
    before do
      ENV["OPENSOP_UI_USER"]     = "admin"
      ENV["OPENSOP_UI_PASSWORD"] = "secret"
    end

    after do
      ENV.delete("OPENSOP_UI_USER")
      ENV.delete("OPENSOP_UI_PASSWORD")
    end

    it "/api-docs returns 200 without credentials" do
      get "/api-docs"
      expect(response).to have_http_status(:ok)
    end

    it "/api-docs/guides/:slug returns 200 without credentials" do
      get "/api-docs/guides/quickstart"
      expect(response).to have_http_status(:ok)
    end

    it "/api-docs/endpoints/:slug returns 200 without credentials" do
      get "/api-docs/endpoints/start-instance"
      expect(response).to have_http_status(:ok)
    end

    it "the rest of the admin UI is still gated (sanity check)" do
      get "/dashboard"
      expect(response).to have_http_status(:unauthorized)
    end

    it "hides the topbar Dashboard link from anonymous visitors" do
      get "/api-docs"
      expect(response.body).not_to match(%r{<a[^>]+href="/dashboard"})
    end

    it "shows the Dashboard link when valid Basic credentials are sent" do
      creds = ActionController::HttpAuthentication::Basic.encode_credentials("admin", "secret")
      get "/api-docs", headers: { "HTTP_AUTHORIZATION" => creds }
      expect(response.body).to match(%r{<a[^>]+href="/dashboard"})
    end
  end

  context "when admin HTTP Basic auth is NOT configured (open dev mode)" do
    it "shows the Dashboard link to anonymous visitors" do
      get "/api-docs"
      expect(response.body).to match(%r{<a[^>]+href="/dashboard"})
    end
  end

  context "command palette modal" do
    it "renders the cmdk container with the dataset on every page" do
      get "/api-docs"
      expect(response.body).to include('data-controller="api-docs-cmdk"')
      expect(response.body).to include('data-api-docs-cmdk-data-value=')
      expect(response.body).to include("Search endpoints, guides, parameters")
    end

    it "includes a search-trigger button wired to open the modal" do
      get "/api-docs"
      expect(response.body).to include('data-action="click->api-docs-cmdk#open"')
    end
  end
end
