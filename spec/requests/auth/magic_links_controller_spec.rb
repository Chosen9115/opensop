require "rails_helper"

RSpec.describe "Auth::MagicLinksController", type: :request do
  describe "POST /auth/magic_links" do
    let!(:user) { create(:user, email: "user@example.com") }

    before do
      allow(Opensop::Auth::Mailer).to receive(:send_magic_link).and_return({ id: "stub" })
    end

    it "renders the 'check your email' confirmation for a known email" do
      expect {
        post "/auth/magic_links", params: { email: user.email, purpose: "sign_in" }
      }.to change { user.magic_link_tokens.where(purpose: "sign_in").count }.by(1)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Check your email")
      expect(response.body).to include(user.email)

      expect(Opensop::Auth::Mailer).to have_received(:send_magic_link).with(
        hash_including(user: user, purpose: "sign_in", host: anything, raw_token: anything)
      )
    end

    it "renders the same confirmation for an unknown email and does NOT issue a token" do
      expect {
        post "/auth/magic_links", params: { email: "nobody@example.com", purpose: "sign_in" }
      }.not_to change { MagicLinkToken.count }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Check your email")
      expect(Opensop::Auth::Mailer).not_to have_received(:send_magic_link)
    end

    it "creates a recovery-purpose token when purpose=recovery" do
      expect {
        post "/auth/magic_links", params: { email: user.email, purpose: "recovery" }
      }.to change { user.magic_link_tokens.where(purpose: "recovery").count }.by(1)

      expect(Opensop::Auth::Mailer).to have_received(:send_magic_link).with(
        hash_including(purpose: "recovery")
      )
    end

    it "normalizes mixed-case emails to lower" do
      expect {
        post "/auth/magic_links", params: { email: "USER@Example.COM" }
      }.to change { user.magic_link_tokens.count }.by(1)
    end

    it "defaults to sign_in purpose when purpose param is missing or invalid" do
      post "/auth/magic_links", params: { email: user.email, purpose: "weird" }
      expect(user.magic_link_tokens.where(purpose: "sign_in").count).to eq(1)
    end

    it "records a magic_link_requested audit event for known and unknown emails" do
      expect {
        post "/auth/magic_links", params: { email: user.email, purpose: "sign_in" }
      }.to change { AuthEvent.where(kind: "magic_link_requested").count }.by(1)

      expect {
        post "/auth/magic_links", params: { email: "ghost@example.com", purpose: "sign_in" }
      }.to change { AuthEvent.where(kind: "magic_link_requested").count }.by(1)
    end

    it "records both magic_link_requested AND recovery_initiated when purpose=recovery" do
      expect {
        post "/auth/magic_links", params: { email: user.email, purpose: "recovery" }
      }.to change { AuthEvent.where(kind: "magic_link_requested").count }.by(1)
        .and change { AuthEvent.where(kind: "recovery_initiated").count }.by(1)
    end
  end

  describe "GET /auth/magic_links/:token" do
    let(:user) { create(:user) }

    it "consumes a sign_in token, signs the user in, and redirects to /dashboard" do
      raw = Opensop::Auth::TokenIssuer.call(user: user, purpose: "sign_in")
      expect {
        get "/auth/magic_links/#{raw}"
      }.to change { AuthSession.where(user: user).count }.by(1)

      expect(response).to redirect_to("/dashboard")
      expect(flash[:notice]).to include("Register a passkey")

      token = user.magic_link_tokens.last
      expect(token.consumed?).to be(true)

      expect(user.reload.last_signed_in_at).to be_present
    end

    it "consumes a recovery token and redirects with the recovery flash" do
      raw = Opensop::Auth::TokenIssuer.call(user: user, purpose: "recovery")
      get "/auth/magic_links/#{raw}"

      expect(response).to redirect_to("/dashboard")
      expect(flash[:notice]).to include("/account/passkeys")
    end

    it "returns 404 for an already-consumed token" do
      raw = Opensop::Auth::TokenIssuer.call(user: user, purpose: "sign_in")
      get "/auth/magic_links/#{raw}"
      get "/auth/magic_links/#{raw}"
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for an expired token" do
      token = create(:magic_link_token, :expired, user: user)
      raw = "fake-not-the-real-one"
      # Build a real token then mark it expired so the digest matches.
      raw_real = SecureRandom.urlsafe_base64(32)
      token.update_columns(token_digest: Digest::SHA256.hexdigest(raw_real), expires_at: 1.minute.ago)
      get "/auth/magic_links/#{raw_real}"
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 when the token's purpose is invitation (wrong route)" do
      raw = Opensop::Auth::TokenIssuer.call(user: user, purpose: "invitation")
      get "/auth/magic_links/#{raw}"
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a non-existent token" do
      get "/auth/magic_links/totally-fake-token"
      expect(response).to have_http_status(:not_found)
    end

    it "records a magic_link_consumed audit event on success" do
      raw = Opensop::Auth::TokenIssuer.call(user: user, purpose: "sign_in")
      expect {
        get "/auth/magic_links/#{raw}"
      }.to change { AuthEvent.where(kind: "magic_link_consumed", user: user).count }.by(1)
    end

    it "records a magic_link_expired audit event on failure" do
      expect {
        get "/auth/magic_links/totally-fake-token"
      }.to change { AuthEvent.where(kind: "magic_link_expired").count }.by(1)
    end
  end

  describe "dev banner gating" do
    let!(:user) { create(:user, email: "test@example.com") }

    context "in development with mailer in log mode" do
      before do
        allow(Rails.env).to receive(:development?).and_return(true)
        ENV["OPENSOP_MAILER_MODE"] = "log"
        allow(Opensop::Auth::Mailer).to receive(:send_magic_link).and_return({ id: "stub" })
      end

      after { ENV.delete("OPENSOP_MAILER_MODE") }

      it "sets @dev_magic_link_url for a known email and renders the banner" do
        post "/auth/magic_links", params: { email: user.email }

        # The controller assigns @dev_magic_link_url when both gates are open
        # and the view passes it to the component, which renders the URL.
        expect(response.body).to match(%r{auth/magic_links/[A-Za-z0-9_-]+})
        expect(response.body.downcase).to include("dev mode")
        expect(response.body).to include(I18n.t("opensop.auth.magic_link_sent.dev.cta"))
      end

      it "does NOT set @dev_magic_link_url for an unknown email" do
        post "/auth/magic_links", params: { email: "ghost@example.com" }

        # No user found -> no token created -> no dev URL.
        expect(response.body.downcase).not_to include("dev mode")
        expect(response.body).not_to include(I18n.t("opensop.auth.magic_link_sent.dev.cta"))
      end
    end

    context "in production" do
      before do
        allow(Rails.env).to receive(:development?).and_return(false)
        allow(Rails.env).to receive(:production?).and_return(true)
        # Stub the mailer so we don't try to actually send via Resend.
        allow(Opensop::Auth::Mailer).to receive(:send_magic_link).and_return({ id: "stub" })
      end

      it "does NOT render the dev banner even with OPENSOP_MAILER_MODE=log" do
        ENV["OPENSOP_MAILER_MODE"] = "log"
        post "/auth/magic_links", params: { email: user.email }
        expect(response.body.downcase).not_to include("dev mode")
        expect(response.body).not_to include(I18n.t("opensop.auth.magic_link_sent.dev.cta"))
      ensure
        ENV.delete("OPENSOP_MAILER_MODE")
      end
    end

    context "in development with mailer in send mode" do
      before do
        allow(Rails.env).to receive(:development?).and_return(true)
        ENV["OPENSOP_MAILER_MODE"] = "send"
        allow(Opensop::Auth::Mailer).to receive(:send_magic_link).and_return({ id: "stub" })
      end

      after { ENV.delete("OPENSOP_MAILER_MODE") }

      it "does NOT render the dev banner" do
        post "/auth/magic_links", params: { email: user.email }
        expect(response.body.downcase).not_to include("dev mode")
        expect(response.body).not_to include(I18n.t("opensop.auth.magic_link_sent.dev.cta"))
      end
    end
  end

  describe "cookie security" do
    let(:user) { create(:user) }
    let(:raw_token) { Opensop::Auth::TokenIssuer.call(user: user, purpose: "sign_in") }

    def consume!
      get "/auth/magic_links/#{raw_token}"
    end

    def session_cookie_header
      header = response.headers["Set-Cookie"]
      Array(header).find { |c| c.to_s.start_with?("#{Authenticatable::COOKIE_NAME}=") }
    end

    it "sets HttpOnly on the session cookie" do
      consume!
      expect(session_cookie_header).to match(/opensop_session=.+HttpOnly/i)
    end

    it "sets SameSite=Lax on the session cookie" do
      consume!
      expect(session_cookie_header).to match(/SameSite=Lax/i)
    end

    it "does NOT set Secure on the session cookie in the test environment" do
      consume!
      expect(session_cookie_header).not_to match(/opensop_session=.+;\s*secure/i)
    end

    it "does not store the raw token in the cookie value (it is signed)" do
      consume!
      cookie_value = session_cookie_header[/opensop_session=([^;]+)/, 1]
      expect(cookie_value).to be_present
      expect(cookie_value).not_to include(raw_token)
    end

    context "when running in production" do
      before do
        allow(Rails.env).to receive(:production?).and_return(true)
      end

      it "sets the Secure flag on the session cookie" do
        # Secure cookies are dropped by Rack on non-https requests, so we
        # must drive the request over https for the cookie to be emitted.
        get "/auth/magic_links/#{raw_token}", headers: { "HTTPS" => "on" }
        expect(session_cookie_header).to match(/opensop_session=.+;\s*secure/i)
      end
    end
  end
end
