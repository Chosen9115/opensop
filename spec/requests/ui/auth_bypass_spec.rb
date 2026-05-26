# frozen_string_literal: true

require "rails_helper"

# Covers the OPENSOP_DISABLE_AUTH env-var bypass for the admin UI.
# Contract:
#   (a) With no env var set, unauthenticated requests still redirect to sign-in.
#   (b) With the flag set + localhost RP_ID, a request with no session cookie
#       is auto-authenticated as the bootstrap admin and renders the dashboard.
#   (c) With the flag set but a real-domain RP_ID (public deployment), the
#       bypass is ignored and the redirect still happens.
#   (d) The bypass does NOT bleed into the API token gate on /sop/*.
RSpec.describe "UI auth bypass via OPENSOP_DISABLE_AUTH", type: :request do
  around do |ex|
    orig_disable = ENV["OPENSOP_DISABLE_AUTH"]
    orig_rp_id   = ENV["OPENSOP_RP_ID"]
    orig_email   = ENV["OPENSOP_BOOTSTRAP_EMAIL"]
    ex.run
  ensure
    if orig_disable.nil?
      ENV.delete("OPENSOP_DISABLE_AUTH")
    else
      ENV["OPENSOP_DISABLE_AUTH"] = orig_disable
    end

    if orig_rp_id.nil?
      ENV.delete("OPENSOP_RP_ID")
    else
      ENV["OPENSOP_RP_ID"] = orig_rp_id
    end

    if orig_email.nil?
      ENV.delete("OPENSOP_BOOTSTRAP_EMAIL")
    else
      ENV["OPENSOP_BOOTSTRAP_EMAIL"] = orig_email
    end
  end

  # (a) Baseline — flag absent, redirect to sign-in is unchanged.
  context "when OPENSOP_DISABLE_AUTH is not set" do
    before do
      ENV.delete("OPENSOP_DISABLE_AUTH")
      ENV.delete("OPENSOP_RP_ID")
    end

    it "redirects unauthenticated GET /dashboard to the sign-in page" do
      get "/dashboard"
      expect(response).to have_http_status(:found)
      expect(response.location).to include("/auth/sign_in")
    end
  end

  # (b) Bypass active on localhost — dashboard accessible without a session.
  context "when OPENSOP_DISABLE_AUTH=true and OPENSOP_RP_ID=localhost" do
    let!(:bootstrap_user) do
      create(:user, email: "bootstrap@example.com")
    end

    before do
      ENV["OPENSOP_DISABLE_AUTH"] = "true"
      ENV["OPENSOP_RP_ID"]        = "localhost"
      ENV["OPENSOP_BOOTSTRAP_EMAIL"] = "bootstrap@example.com"
    end

    it "returns 200 for GET /dashboard without a session cookie" do
      get "/dashboard"

      expect(response).to have_http_status(:ok)
      expect(response).not_to redirect_to(%r{/auth/sign_in})
    end
  end

  # (c) Bypass ignored on a public deployment (real domain RP_ID).
  context "when OPENSOP_DISABLE_AUTH=true but OPENSOP_RP_ID is a real domain" do
    before do
      ENV["OPENSOP_DISABLE_AUTH"] = "true"
      ENV["OPENSOP_RP_ID"]        = "opensop.example.com"
    end

    it "still redirects unauthenticated GET /dashboard to sign-in" do
      get "/dashboard"
      expect(response).to have_http_status(:found)
      expect(response.location).to include("/auth/sign_in")
    end
  end

  # (d) API token gate on /sop/ is unaffected by OPENSOP_DISABLE_AUTH.
  context "when OPENSOP_DISABLE_AUTH=true and OPENSOP_RP_ID=localhost" do
    around do |ex|
      orig_api_token = ENV["OPENSOP_API_TOKEN"]
      Sop::ApplicationController.class_variable_set(:@@unauth_warned, false)
      ex.run
    ensure
      if orig_api_token.nil?
        ENV.delete("OPENSOP_API_TOKEN")
      else
        ENV["OPENSOP_API_TOKEN"] = orig_api_token
      end
    end

    before do
      ENV["OPENSOP_DISABLE_AUTH"] = "true"
      ENV["OPENSOP_RP_ID"]        = "localhost"
      ENV["OPENSOP_API_TOKEN"]    = "real-api-token"
    end

    it "returns 401 for GET /sop/ without X-SOP-Token (bypass does not affect API gate)" do
      get "/sop/"
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
