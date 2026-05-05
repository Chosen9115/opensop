# frozen_string_literal: true

# Helpers for specs that need to sign a user in via the cookie-backed
# session flow used by Authenticatable. The cleanest path is the end-to-end
# one: issue a magic-link token, then GET the magic-link URL with the raw
# token, which sets the signed cookie naturally. Use #sign_in_via_magic_link
# in the spec's before block.
#
# Works for both request specs (`type: :request`, Rack::Test) and system
# specs (`type: :system`, Capybara). The helper detects which is in scope
# and dispatches accordingly.
module AuthTestHelpers
  # Sign the given user in by issuing a magic-link token directly and
  # consuming it through GET /auth/magic_links/:token. After this call,
  # subsequent `get`/`post` (request specs) or `visit` (system specs)
  # requests carry the session cookie automatically.
  def sign_in_via_magic_link(user)
    raw = Opensop::Auth::TokenIssuer.call(user: user, purpose: "sign_in")

    if respond_to?(:visit) && respond_to?(:page) && page.respond_to?(:driver)
      # System spec — drive Capybara so the cookie lands in the browser.
      visit "/auth/magic_links/#{raw}"
    else
      # Request spec — Rack::Test sets cookies on the test cookie jar.
      get "/auth/magic_links/#{raw}"
      expect(response).to have_http_status(:found)
    end
  end
end

RSpec.configure do |config|
  config.include AuthTestHelpers, type: :request
  config.include AuthTestHelpers, type: :system
end
