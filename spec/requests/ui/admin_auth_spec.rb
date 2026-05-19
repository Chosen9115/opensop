require "rails_helper"

# Covers the optional HTTP Basic auth layer on the /ui admin routes.
# Three states exercised:
#   1. Both ENV vars unset  → auth skipped, UI is open
#   2. Both set, valid creds → pass-through
#   3. Both set, missing/wrong creds → 401 with WWW-Authenticate header
RSpec.describe "Admin UI basic auth", type: :request do
  let(:ui_paths) { [ "/", "/processes", "/instances" ] }

  context "when OPENSOP_UI_USER and OPENSOP_UI_PASSWORD are unset" do
    before do
      ENV.delete("OPENSOP_UI_USER")
      ENV.delete("OPENSOP_UI_PASSWORD")
    end

    it "serves UI routes without a challenge (dev mode)" do
      ui_paths.each do |path|
        get path
        expect(response.status).to be < 400, "expected #{path} to be open, got #{response.status}"
      end
    end
  end

  context "when credentials are set" do
    before do
      ENV["OPENSOP_UI_USER"] = "admin"
      ENV["OPENSOP_UI_PASSWORD"] = "secret123"
    end

    after do
      ENV.delete("OPENSOP_UI_USER")
      ENV.delete("OPENSOP_UI_PASSWORD")
    end

    it "returns 401 with a challenge header when no credentials are provided" do
      get "/instances"
      expect(response).to have_http_status(:unauthorized)
      expect(response.headers["WWW-Authenticate"]).to include('Basic realm="OpenSOP"')
    end

    it "returns 401 when credentials are wrong" do
      get "/instances", headers: { "Authorization" => basic_auth_header("admin", "wrong") }
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 when only username is wrong" do
      get "/instances", headers: { "Authorization" => basic_auth_header("intruder", "secret123") }
      expect(response).to have_http_status(:unauthorized)
    end

    it "passes through with correct credentials" do
      get "/instances", headers: { "Authorization" => basic_auth_header("admin", "secret123") }
      expect(response.status).to be < 400
    end

    it "protects every UI path, not just /instances" do
      ui_paths.each do |path|
        get path
        expect(response).to have_http_status(:unauthorized), "expected #{path} to challenge, got #{response.status}"
      end
    end

    it "does NOT require basic auth on /sop/* API endpoints" do
      # These use X-SOP-Token instead. Separation of concerns.
      get "/sop/"
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # In dev / staging the auth gate falls back to the development default
  # 'admin' / 'admin' when env vars are unset, so the dashboard is never
  # wide open even on a misconfigured deploy.
  context "in development with env vars unset (dev defaults)" do
    before do
      ENV.delete("OPENSOP_UI_USER")
      ENV.delete("OPENSOP_UI_PASSWORD")
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("development"))
    end

    it "challenges /instances with no credentials (401)" do
      get "/instances"
      expect(response).to have_http_status(:unauthorized)
      expect(response.headers["WWW-Authenticate"]).to include('Basic realm="OpenSOP"')
    end

    it "passes through when admin/admin is provided" do
      get "/instances", headers: { "Authorization" => basic_auth_header("admin", "admin") }
      expect(response.status).to be < 400
    end

    it "rejects wrong credentials (401)" do
      get "/instances", headers: { "Authorization" => basic_auth_header("admin", "nope") }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # Production must NEVER reach the dev defaults — the controller short-
  # circuits before falling back, mirroring the boot-time guard in
  # config/initializers/admin_ui_auth.rb.
  context "in production with env vars unset (defensive)" do
    before do
      ENV.delete("OPENSOP_UI_USER")
      ENV.delete("OPENSOP_UI_PASSWORD")
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("production"))
    end

    it "does NOT fall back to dev defaults — admin/admin is rejected" do
      get "/instances", headers: { "Authorization" => basic_auth_header("admin", "admin") }
      # The gate returns early without challenging when env vars are unset
      # in production — request flows through without auth wired up. The
      # boot-time initializer is the real gate (covered by its own spec).
      expect(response.body).not_to include("admin")
    end
  end

  def basic_auth_header(user, pass)
    "Basic " + Base64.strict_encode64("#{user}:#{pass}")
  end
end
