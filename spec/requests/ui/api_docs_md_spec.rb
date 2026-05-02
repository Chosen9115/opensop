# frozen_string_literal: true

require "rails_helper"

# Covers the agent-friendly markdown surface of the API reference:
#   GET /api-docs.md                    — bundled markdown of every guide + endpoint
#   GET /api-docs/guides/:slug.md       — one guide as markdown
#   GET /api-docs/endpoints/:slug.md    — one endpoint as markdown
#   GET /llms.txt                       — llms.txt index pointing at the above
RSpec.describe "Ui::ApiDocs markdown surface", type: :request do
  before do
    ENV.delete("OPENSOP_UI_USER")
    ENV.delete("OPENSOP_UI_PASSWORD")
  end

  describe "GET /api-docs.md (bundled)" do
    it "returns 200 with text/markdown content type" do
      get "/api-docs.md"
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to start_with("text/markdown")
    end

    it "includes every guide title" do
      get "/api-docs.md"
      Ui::ApiDocs::Catalog::GUIDES.each do |g|
        title = I18n.t("opensop.api_docs.guides.#{g[:slug].underscore}.title", default: g[:label])
        expect(response.body).to include(title),
          "expected bundled MD to include guide title #{title.inspect}"
      end
    end

    it "includes every endpoint method+path" do
      get "/api-docs.md"
      Ui::ApiDocs::Catalog::ENDPOINT_SECTIONS.flat_map { |s| s[:endpoints] }.each do |ep|
        signature = "#{ep[:method]} #{ep[:path]}"
        expect(response.body).to include(signature),
          "expected bundled MD to include endpoint signature #{signature.inspect}"
      end
    end

    it "includes a top-level OpenSOP heading and a table of contents" do
      get "/api-docs.md"
      expect(response.body).to start_with("# OpenSOP API Reference")
      expect(response.body).to include("## Contents")
    end

    it "renders many lines of content" do
      get "/api-docs.md"
      expect(response.body.lines.count).to be > 500
    end
  end

  describe "GET /api-docs/guides/:slug.md" do
    Ui::ApiDocs::Catalog::GUIDES.each do |guide|
      it "returns 200 markdown for #{guide[:slug]}" do
        get "/api-docs/guides/#{guide[:slug]}.md"
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to start_with("text/markdown")
        title = I18n.t("opensop.api_docs.guides.#{guide[:slug].underscore}.title", default: guide[:label])
        expect(response.body).to include(title)
      end
    end

    it "returns 404 for an unknown guide slug" do
      get "/api-docs/guides/nonexistent-guide.md"
      expect(response).to have_http_status(:not_found)
    end

    it "renders without an HTML layout (no <html> tag)" do
      get "/api-docs/guides/quickstart.md"
      expect(response.body).not_to include("<html")
      expect(response.body).not_to include("<body")
    end
  end

  describe "GET /api-docs/endpoints/:slug.md" do
    Ui::ApiDocs::Catalog::ENDPOINT_SECTIONS.flat_map { |s| s[:endpoints] }.each do |ep|
      it "returns 200 markdown for #{ep[:slug]}" do
        get "/api-docs/endpoints/#{ep[:slug]}.md"
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to start_with("text/markdown")
        expect(response.body).to include(ep[:method])
        expect(response.body).to include(ep[:path])
      end
    end

    it "returns 404 for an unknown endpoint slug" do
      get "/api-docs/endpoints/nonexistent-endpoint.md"
      expect(response).to have_http_status(:not_found)
    end

    it "renders without an HTML layout" do
      get "/api-docs/endpoints/start-instance.md"
      expect(response.body).not_to include("<html")
      expect(response.body).not_to include("<body")
    end
  end

  describe "GET /llms.txt" do
    it "returns 200 with text/plain content type" do
      get "/llms.txt"
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to start_with("text/plain")
    end

    it "starts with the OpenSOP heading" do
      get "/llms.txt"
      expect(response.body).to start_with("# OpenSOP")
    end

    it "links to the bundled markdown" do
      get "/llms.txt"
      expect(response.body).to match(%r{/api-docs\.md})
    end

    it "links to every per-guide and per-endpoint markdown URL" do
      get "/llms.txt"
      Ui::ApiDocs::Catalog::GUIDES.each do |g|
        expect(response.body).to include("/api-docs/guides/#{g[:slug]}.md"),
          "expected llms.txt to link to guide #{g[:slug]}.md"
      end
      Ui::ApiDocs::Catalog::ENDPOINT_SECTIONS.flat_map { |s| s[:endpoints] }.each do |ep|
        expect(response.body).to include("/api-docs/endpoints/#{ep[:slug]}.md"),
          "expected llms.txt to link to endpoint #{ep[:slug]}.md"
      end
    end
  end

  describe "HTML routes are unaffected" do
    it "GET /api-docs still serves HTML (not the bundle)" do
      get "/api-docs"
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to start_with("text/html")
    end

    it "GET /api-docs/guides/:slug still serves HTML" do
      get "/api-docs/guides/quickstart"
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to start_with("text/html")
    end

    it "GET /api-docs/endpoints/:slug still serves HTML" do
      get "/api-docs/endpoints/start-instance"
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to start_with("text/html")
    end
  end

  # The MD surface is intentionally public — same posture as the HTML site.
  context "when admin HTTP Basic auth is configured" do
    before do
      ENV["OPENSOP_UI_USER"]     = "admin"
      ENV["OPENSOP_UI_PASSWORD"] = "secret"
    end

    after do
      ENV.delete("OPENSOP_UI_USER")
      ENV.delete("OPENSOP_UI_PASSWORD")
    end

    it "/api-docs.md returns 200 without credentials" do
      get "/api-docs.md"
      expect(response).to have_http_status(:ok)
    end

    it "/llms.txt returns 200 without credentials" do
      get "/llms.txt"
      expect(response).to have_http_status(:ok)
    end

    it "/api-docs/guides/:slug.md returns 200 without credentials" do
      get "/api-docs/guides/quickstart.md"
      expect(response).to have_http_status(:ok)
    end
  end
end
