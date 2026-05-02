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

    it "advertises a Project metadata block with source / issues / license / spec version" do
      get "/llms.txt"
      expect(response.body).to include("## Project")
      expect(response.body).to include("**Source:**")
      expect(response.body).to include("**Issues:**")
      expect(response.body).to include("**License:**")
      expect(response.body).to include("**API spec version:**")
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

  describe "GET /sitemap.xml" do
    it "returns 200 with application/xml content type" do
      get "/sitemap.xml"
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to start_with("application/xml")
    end

    it "is a well-formed urlset declaring the xhtml namespace" do
      get "/sitemap.xml"
      expect(response.body).to start_with(%(<?xml version="1.0" encoding="UTF-8"?>))
      expect(response.body).to include('xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"')
      expect(response.body).to include('xmlns:xhtml="http://www.w3.org/1999/xhtml"')
    end

    it "lists every HTML doc URL with a markdown alternate" do
      get "/sitemap.xml"
      # Index, bundled, llms.txt, every guide, every endpoint
      expect(response.body).to include("<loc>")
      expect(response.body).to match(%r{<loc>[^<]*/api-docs</loc>})
      expect(response.body).to match(%r{<loc>[^<]*/api-docs\.md</loc>})
      expect(response.body).to match(%r{<loc>[^<]*/llms\.txt</loc>})

      Ui::ApiDocs::Catalog::GUIDES.each do |g|
        expect(response.body).to include("/api-docs/guides/#{g[:slug]}</loc>")
        expect(response.body).to include(%(href="http://www.example.com/api-docs/guides/#{g[:slug]}.md"))
      end
      Ui::ApiDocs::Catalog::ENDPOINT_SECTIONS.flat_map { |s| s[:endpoints] }.each do |ep|
        expect(response.body).to include("/api-docs/endpoints/#{ep[:slug]}</loc>")
        expect(response.body).to include(%(href="http://www.example.com/api-docs/endpoints/#{ep[:slug]}.md"))
      end
    end

    it "supports ETag and 304" do
      get "/sitemap.xml"
      etag = response.headers["ETag"]
      expect(etag).to be_present
      get "/sitemap.xml", headers: { "If-None-Match" => etag }
      expect(response).to have_http_status(:not_modified)
    end
  end

  describe "dev-mode ETag fingerprint" do
    # In non-production, the etag is derived from the mtime of the docs
    # source files. Touching a partial should bust an existing etag so
    # agents see the new content without restarting the server.
    let(:partial) { Rails.root.join("app/views/ui/api_docs/guides/_quickstart.md.erb") }

    it "changes when a docs source file is touched" do
      get "/api-docs/guides/quickstart.md"
      etag_before = response.headers["ETag"]
      File.utime(Time.now + 1, Time.now + 1, partial)
      get "/api-docs/guides/quickstart.md"
      etag_after = response.headers["ETag"]
      expect(etag_after).not_to eq(etag_before)
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

  # The bundle and per-page MD must contain only markdown — no Tailwind class
  # patterns, no ERB residue, no <html>/<body> tags. Catches the easy case
  # where a partial accidentally embeds chrome from the HTML version.
  describe "content quality" do
    let(:md_paths) do
      [
        "/api-docs.md",
        *Ui::ApiDocs::Catalog::GUIDES.map     { |g| "/api-docs/guides/#{g[:slug]}.md" },
        *Ui::ApiDocs::Catalog::ENDPOINT_SECTIONS.flat_map { |s| s[:endpoints] }.map { |ep| "/api-docs/endpoints/#{ep[:slug]}.md" }
      ]
    end

    it "every MD response contains no Tailwind utility class patterns" do
      md_paths.each do |path|
        get path
        # Tailwind utilities show up as class="..." attributes; the markdown
        # surface should never serve them.
        expect(response.body).not_to match(/class\s*=\s*["'][^"']*\b(?:bg-|text-|flex|grid|px-|py-|mx-|my-|rounded)/),
          "expected #{path} to contain no Tailwind class attributes"
      end
    end

    it "every MD response contains no ERB residue" do
      md_paths.each do |path|
        get path
        expect(response.body).not_to include("<%"),
          "expected #{path} to have no leftover ERB tags"
        expect(response.body).not_to include("%>"),
          "expected #{path} to have no leftover ERB tags"
      end
    end

    it "every MD response is layout-free (no <html>, <body>, <head>)" do
      md_paths.each do |path|
        get path
        expect(response.body).not_to match(/<html[\s>]/i),  "expected #{path} to have no <html> tag"
        expect(response.body).not_to match(/<body[\s>]/i),  "expected #{path} to have no <body> tag"
        expect(response.body).not_to match(/<head[\s>]/i),  "expected #{path} to have no <head> tag"
      end
    end

    it "the bundle has balanced fenced code blocks" do
      get "/api-docs.md"
      fence_count = response.body.scan(/^```/).size
      expect(fence_count).to be_even,
        "expected ``` fences to be balanced, found #{fence_count}"
    end
  end

  # Agents that re-fetch should get a 304 from the etag — re-rendering a
  # 50KB bundle on every poll is a waste.
  describe "HTTP caching" do
    it "/api-docs.md returns an ETag header" do
      get "/api-docs.md"
      expect(response.headers["ETag"]).to be_present
    end

    it "/api-docs.md returns 304 when If-None-Match matches" do
      get "/api-docs.md"
      etag = response.headers["ETag"]
      get "/api-docs.md", headers: { "If-None-Match" => etag }
      expect(response).to have_http_status(:not_modified)
    end

    it "/api-docs/guides/:slug.md returns an ETag and supports 304" do
      get "/api-docs/guides/quickstart.md"
      etag = response.headers["ETag"]
      expect(etag).to be_present
      get "/api-docs/guides/quickstart.md", headers: { "If-None-Match" => etag }
      expect(response).to have_http_status(:not_modified)
    end

    it "/api-docs/endpoints/:slug.md returns an ETag and supports 304" do
      get "/api-docs/endpoints/start-instance.md"
      etag = response.headers["ETag"]
      expect(etag).to be_present
      get "/api-docs/endpoints/start-instance.md", headers: { "If-None-Match" => etag }
      expect(response).to have_http_status(:not_modified)
    end

    it "/llms.txt returns an ETag and supports 304" do
      get "/llms.txt"
      etag = response.headers["ETag"]
      expect(etag).to be_present
      get "/llms.txt", headers: { "If-None-Match" => etag }
      expect(response).to have_http_status(:not_modified)
    end

    it "the etag differs between MD and HTML for the same slug" do
      get "/api-docs/guides/quickstart"
      html_etag = response.headers["ETag"]
      get "/api-docs/guides/quickstart.md"
      md_etag = response.headers["ETag"]
      expect(html_etag).not_to eq(md_etag)
    end
  end

  # HTML pages should advertise the markdown mirror via <link rel="alternate">
  # so agents discovering the HTML can find the MD without guessing.
  describe "HTML pages link to their MD alternate" do
    it "the index links to the bundled markdown" do
      get "/api-docs"
      expect(response.body).to include('<link rel="alternate" type="text/markdown" href="/api-docs.md"')
    end

    it "a guide page links to its slug-specific markdown" do
      get "/api-docs/guides/quickstart"
      expect(response.body).to include('<link rel="alternate" type="text/markdown" href="/api-docs/guides/quickstart.md"')
    end

    it "an endpoint page links to its slug-specific markdown" do
      get "/api-docs/endpoints/start-instance"
      expect(response.body).to include('<link rel="alternate" type="text/markdown" href="/api-docs/endpoints/start-instance.md"')
    end
  end

  # /api-docs.md MUST resolve to ApiDocsController#bundled. The HTML index
  # route at /api-docs(.:format) used to greedily match `.md` and serve the
  # Quickstart HTML through the index action — keep this regression in
  # check by asserting the recognized action for each path.
  describe "route → action wiring" do
    def recognize(path)
      Rails.application.routes.recognize_path(path, method: :get)
    end

    it "GET /api-docs.md routes to ui/api_docs#bundled" do
      expect(recognize("/api-docs.md")).to include(controller: "ui/api_docs", action: "bundled")
    end

    it "GET /api-docs/guides/:slug.md routes to ui/api_docs#guide with format=md" do
      result = recognize("/api-docs/guides/quickstart.md")
      expect(result).to include(controller: "ui/api_docs", action: "guide", slug: "quickstart")
    end

    it "GET /api-docs/endpoints/:slug.md routes to ui/api_docs#endpoint with format=md" do
      result = recognize("/api-docs/endpoints/start-instance.md")
      expect(result).to include(controller: "ui/api_docs", action: "endpoint", slug: "start-instance")
    end

    it "GET /api-docs (no format) routes to ui/api_docs#index" do
      expect(recognize("/api-docs")).to include(controller: "ui/api_docs", action: "index")
    end

    it "GET /llms.txt routes to ui/api_docs#llms_txt" do
      expect(recognize("/llms.txt")).to include(controller: "ui/api_docs", action: "llms_txt")
    end

    it "GET /sitemap.xml routes to ui/api_docs#sitemap" do
      expect(recognize("/sitemap.xml")).to include(controller: "ui/api_docs", action: "sitemap")
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
