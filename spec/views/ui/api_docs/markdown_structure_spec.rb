# frozen_string_literal: true

require "rails_helper"

# Per-partial structural assertions for the markdown surface. The request
# specs prove the routes wire up; these specs prove each individual guide
# and endpoint partial keeps its expected sections, code blocks, and
# auth-callout markup. A regression here will catch a guide partial that
# accidentally lost its "Next steps" block, an endpoint partial missing
# its "Code examples" or auth callout, or a code fence without a
# language tag.
RSpec.describe "Ui::ApiDocs markdown partials structure", type: :request do
  # ---------------------------------------------------------------------
  # Shared expectations
  # ---------------------------------------------------------------------

  shared_examples "every fenced code block has a language tag" do |path|
    it "has a language tag on every fenced code block (#{path})" do
      get path
      # Every opening fence (one that starts a block, i.e. an even-indexed
      # ``` line) should carry a language tag like ```yaml / ```json /
      # ```bash. Closing fences are bare ```.
      lines        = response.body.lines
      open_fences  = []
      in_block     = false
      lines.each do |line|
        next unless line.start_with?("```")
        if in_block
          in_block = false
        else
          open_fences << line.strip
          in_block = true
        end
      end
      bare = open_fences.reject { |f| f.match?(/\A```[a-z][a-z0-9+-]*\z/) }
      expect(bare).to be_empty,
        "expected every opening fence in #{path} to have a language tag, got bare: #{bare.inspect}"
    end
  end

  # ---------------------------------------------------------------------
  # Guide partials
  # ---------------------------------------------------------------------

  describe "guide partials" do
    EXPECTED_GUIDE_SECTIONS = {
      "quickstart"     => [ "What you'll build", "Lifecycle", "Next steps" ],
      "authentication" => [ "Outbound calls", "Inbound triggers", "Webhook callbacks" ],
      "process-format" => [ "Anatomy", "Step types", "References" ],
      "errors"         => [ "Shape", "Status codes", "Retries" ],
      "versioning"     => [ "API version", "Process versions" ]
    }.freeze

    EXPECTED_GUIDE_SECTIONS.each do |slug, sections|
      context "/#{slug}.md" do
        let(:path) { "/api-docs/guides/#{slug}.md" }

        it "starts with an H2 heading" do
          get path
          expect(response.body.lines.first).to match(/\A##\s+\S/)
        end

        sections.each do |label|
          it "contains the '#{label}' section" do
            get path
            # Match the section as a markdown heading (any depth ##+).
            expect(response.body).to match(/^#+\s.*#{Regexp.escape(label)}/i),
              "expected #{path} to contain a heading with #{label.inspect}"
          end
        end

        include_examples "every fenced code block has a language tag", "/api-docs/guides/#{slug}.md"
      end
    end
  end

  # ---------------------------------------------------------------------
  # Endpoint partials
  # ---------------------------------------------------------------------

  describe "endpoint partials" do
    Ui::ApiDocs::Catalog::ENDPOINT_SECTIONS.flat_map { |s| s[:endpoints] }.each do |ep|
      context "/#{ep[:slug]}.md" do
        let(:path) { "/api-docs/endpoints/#{ep[:slug]}.md" }

        it "starts with the method + path as an H2 heading" do
          get path
          first_line = response.body.lines.first.to_s.strip
          expect(first_line).to start_with("##"),
            "expected #{path} to start with an H2 heading, got #{first_line.inspect}"
          expect(first_line).to include(ep[:method])
          expect(first_line).to include(ep[:path])
        end

        it "starts with an AUTH blockquote describing how the endpoint authenticates" do
          get path
          # Every endpoint partial should explain its auth posture in a
          # blockquote near the top — bearer token for /sop/* endpoints,
          # HMAC for /sop/triggers/*, single-use ULID for /sop/webhooks/*.
          expect(response.body).to match(%r{^> \*\*Auth:\*\*}),
            "expected #{path} to begin with a `> **Auth:**` blockquote"
        end

        it "documents at least one code example with curl" do
          get path
          expect(response.body).to match(/```bash\n.*curl/m),
            "expected #{path} to contain a curl example in a ```bash code block"
        end

        # Endpoints that require a JSON body in the request: start-instance,
        # submit-step, register-process. The other POSTs (cancel-instance,
        # fire-trigger, deliver-callback) carry no app-level request body.
        if %w[start-instance submit-step register-process].include?(ep[:slug])
          it "documents a Request body section" do
            get path
            expect(response.body).to match(/^### .*Request body/i)
          end
        end

        it "documents a Response section" do
          get path
          expect(response.body).to match(/^### .*Response/i)
        end

        include_examples "every fenced code block has a language tag", "/api-docs/endpoints/#{ep[:slug]}.md"
      end
    end
  end

  # ---------------------------------------------------------------------
  # Bundle-level invariants
  # ---------------------------------------------------------------------

  describe "the bundle (/api-docs.md)" do
    it "every fenced code block has a language tag" do
      get "/api-docs.md"
      lines        = response.body.lines
      open_fences  = []
      in_block     = false
      lines.each do |line|
        next unless line.start_with?("```")
        if in_block
          in_block = false
        else
          open_fences << line.strip
          in_block = true
        end
      end
      bare = open_fences.reject { |f| f.match?(/\A```[a-z][a-z0-9+-]*\z/) }
      expect(bare).to be_empty,
        "bundle has untagged fences: #{bare.inspect}"
    end

    it "renders a stable body for repeat fetches (no timestamp drift)" do
      get "/api-docs.md"
      first  = response.body
      get "/api-docs.md"
      second = response.body
      expect(first).to eq(second)
    end

    # Every link in the table-of-contents that targets an in-document
    # anchor (e.g. `#guide-quickstart`) must have a matching anchor in
    # the body. Catches a partial that drops or renames its `<a id>`.
    it "every TOC anchor link resolves to an anchor in the body" do
      get "/api-docs.md"
      anchor_links = response.body.scan(/\]\(#([^)\s]+)\)/).flatten.uniq
      expect(anchor_links).not_to be_empty, "bundled MD has no in-document anchor links"

      anchor_links.each do |anchor|
        # Markdown TOCs may target anchors via either an HTML `<a id>` or
        # a heading whose auto-generated slug matches.
        html_anchor    = response.body.include?(%(id="#{anchor}"))
        heading_match  = response.body.match(/^#+\s+#{Regexp.escape(anchor.gsub('-', ' '))}\b/i)
        expect(html_anchor || heading_match).to be_truthy,
          "expected bundled MD to define anchor ##{anchor} (via <a id> or matching heading)"
      end
    end

    it "the contents block lists every guide and endpoint" do
      get "/api-docs.md"
      Ui::ApiDocs::Catalog::GUIDES.each do |g|
        expect(response.body).to include("(#guide-#{g[:slug]})")
      end
      Ui::ApiDocs::Catalog::ENDPOINT_SECTIONS.flat_map { |s| s[:endpoints] }.each do |ep|
        expect(response.body).to include("(#endpoint-#{ep[:slug]})")
      end
    end
  end
end
