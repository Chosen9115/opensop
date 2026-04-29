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

  it "renders the page heading" do
    get "/api-docs"
    # Rails escapes "&" to "&amp;" in HTML output.
    expect(response.body).to include("API &amp; SDK")
  end

  it "documents every public /sop/* endpoint path" do
    get "/api-docs"
    endpoint_paths.each do |path|
      expect(response.body).to include(path),
        "expected /api-docs body to include endpoint path #{path}"
    end
  end

  it "mentions the X-SOP-Token auth header and OPENSOP_API_TOKEN env var" do
    get "/api-docs"
    expect(response.body).to include("X-SOP-Token")
    expect(response.body).to include("OPENSOP_API_TOKEN")
  end
end
