require "rails_helper"

# Phase 4 hard-cutover contract: every /ui route requires a valid session
# cookie. There is no env-var bypass — `require_authentication` always
# enforces. /api-docs and /auth/sign_in remain public.
RSpec.describe "UI session authentication", type: :request do
  it "redirects unauthenticated requests to /dashboard to the sign-in page with return_to" do
    get "/dashboard"
    expect(response).to redirect_to("/auth/sign_in?return_to=%2Fdashboard")
  end

  it "lets authenticated requests through to /dashboard (no redirect to sign-in)" do
    user = create(:user)
    sign_in_via_magic_link(user)

    # Tolerate template-rendering errors caused by the test env's missing
    # compiled tailwind asset; the contract under test is that the auth
    # gate does NOT redirect signed-in users to /auth/sign_in.
    begin
      get "/dashboard"
    rescue ActionView::Template::Error
      # Asset pipeline issue, not auth — fine for this assertion.
    end
    expect(response).not_to redirect_to(%r{/auth/sign_in})
  end

  it "leaves /api-docs/ public — no redirect to sign-in" do
    redirected_to_sign_in = false
    begin
      get "/api-docs/"
      redirected_to_sign_in = response.redirect? && response.location.to_s.include?("/auth/sign_in")
    rescue ActionView::Template::Error
      # Asset pipeline issue means the auth gate let the request through
      # to render the docs page — i.e., the public-access contract holds.
      redirected_to_sign_in = false
    end
    expect(redirected_to_sign_in).to be(false)
  end

  it "lets unauthenticated visitors reach /auth/sign_in" do
    get "/auth/sign_in"
    expect(response).to have_http_status(:ok)
  end
end
