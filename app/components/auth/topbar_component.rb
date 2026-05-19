# frozen_string_literal: true

module Auth
  # Slim top bar shown on the unauthenticated auth pages (sign-in,
  # magic-link-sent). Mirrors the SidebarComponent brand block: 4-square
  # logo, OpenSOP wordmark, version pill — plus a small set of marketing
  # links on the right (Docs only for now; Status/Contact are placeholders
  # disabled with `aria-disabled` until destinations exist).
  class TopbarComponent < ViewComponent::Base
    def version_label
      if defined?(Opensop::VERSION)
        "v#{Opensop::VERSION}"
      else
        "v0.2"
      end
    end
  end
end
