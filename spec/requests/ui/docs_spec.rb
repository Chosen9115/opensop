# frozen_string_literal: true

require "rails_helper"

# Covers GET /docs and GET /docs/:path — project documentation rendered from
# docs/*.md. Route defined in config/routes/ui.rb as :ui_docs.
RSpec.describe "Ui::Docs", type: :request do
  before do
    ENV.delete("OPENSOP_UI_USER")
    ENV.delete("OPENSOP_UI_PASSWORD")
  end

  describe "GET /docs" do
    it "renders the index welcome page with 200" do
      get "/docs"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Documentation")
    end

    it "includes the sidebar doc list" do
      get "/docs"
      expect(response.body).to include("href")
    end
  end

  describe "GET /docs/architecture" do
    it "responds 200 and renders the architecture doc" do
      get "/docs/architecture"
      expect(response).to have_http_status(:ok)
      # The architecture.md file exists in docs/ — rendered HTML will have <h
      expect(response.body).to match(/<h[1-6]/)
    end
  end

  describe "GET /docs/AGENT_GUIDE" do
    it "responds 200 and renders the agent guide doc" do
      get "/docs/AGENT_GUIDE"
      expect(response).to have_http_status(:ok)
      expect(response.body).to match(/<h[1-6]/)
    end
  end

  describe "path traversal protection" do
    it "rejects encoded ../ sequences (double-encoded percent)" do
      get "/docs/..%2F..%2Fconfig%2Fdatabase"
      expect(response).to have_http_status(:not_found)
    end

    it "rejects a path with literal dots via constraint (route won't match)" do
      get "/docs/../config/database"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "non-existent doc" do
    it "returns 404 for a doc that does not exist" do
      get "/docs/nonexistent-totally-fake-doc"
      expect(response).to have_http_status(:not_found)
    end
  end
end
