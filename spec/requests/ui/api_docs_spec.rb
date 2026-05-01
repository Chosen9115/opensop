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
end
