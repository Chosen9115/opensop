# frozen_string_literal: true

module Ui
  # Serves project documentation from docs/*.md as rendered HTML.
  #
  # Security: path traversal is prevented at multiple layers —
  #   1. Route constraint allows only [a-zA-Z0-9_\-/]
  #   2. Param is rejected if it contains "..", leading "/", null bytes,
  #      or characters outside the allow-list
  #   3. Resolved path must start with Rails.root/docs/ (canonical prefix check)
  #   4. File.file? rejects directories and non-existent paths
  #
  # The layout ("docs") renders a sidebar driven by @docs_index plus the
  # @html_content produced here. The show template is intentionally empty.
  class DocsController < ApplicationController
    layout "docs"

    # Skip the activity-rail queries — this page has no rail.
    skip_before_action :load_rail_data
    def show_rail? = false

    # Fallback HTML shown when path == "index" and docs/index.md doesn't exist.
    WELCOME_HTML = <<~HTML.freeze
      <h1>Welcome to OpenSOP Docs</h1>
      <p>Pick a guide from the sidebar to get started.</p>
      <ul>
        <li><strong>Architecture</strong> — how the engine works end-to-end</li>
        <li><strong>Process Authoring</strong> — write your first SOP in YAML</li>
        <li><strong>Agent Guide</strong> — integrate agents with the API</li>
        <li><strong>Deploy on Fly</strong> — one-command production deployment</li>
      </ul>
    HTML

    DOCS_ROOT = Rails.root.join("docs").freeze
    ALLOWED_PATH_RE = /\A[a-zA-Z0-9_\-\/]+\z/

    def show
      path_param = (params[:path] || "index").to_s

      # Layer 2: param allow-list (belt-and-suspenders on top of route constraint)
      unless ALLOWED_PATH_RE.match?(path_param) &&
             !path_param.include?("..") &&
             !path_param.start_with?("/") &&
             !path_param.include?("\0")
        raise ActionController::RoutingError, "Not Found"
      end

      target = DOCS_ROOT.join("#{path_param}.md")

      # Layer 3: canonical prefix check
      unless target.to_s.start_with?(DOCS_ROOT.to_s + "/")
        raise ActionController::RoutingError, "Not Found"
      end

      if path_param == "index" && !File.file?(target)
        # Welcome landing when no index.md exists
        @html_content = WELCOME_HTML
      else
        # Layer 4: must be a real file
        raise ActionController::RoutingError, "Not Found" unless File.file?(target)

        markdown = File.read(target, encoding: "UTF-8")
        @html_content = Commonmarker.to_html(markdown)
      end

      @docs_index = list_docs
    end

    private

    # Returns [{slug:, title:}] for all *.md files under docs/, sorted
    # alphabetically by slug. Title comes from the first # Heading in the
    # file, falling back to the humanized filename.
    def list_docs
      @_docs_index ||= begin
        Dir[DOCS_ROOT.join("*.md")].sort.map do |path|
          slug = File.basename(path, ".md")
          title = extract_title(path, slug)
          { slug: slug, title: title }
        end
      end
    end

    def extract_title(path, fallback_slug)
      File.foreach(path) do |line|
        if (m = line.match(/\A#\s+(.+)/))
          return m[1].strip
        end
      end
      fallback_slug.tr("-_", " ").split.map(&:capitalize).join(" ")
    rescue
      fallback_slug.humanize
    end
  end
end
