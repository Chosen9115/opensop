require "rails_helper"

RSpec.describe "Auth::SessionsController", type: :request do
  describe "GET /auth/sign_in" do
    it "renders 200 for unauthenticated visitors" do
      get "/auth/sign_in"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sign in to OpenSOP")
    end

    it "redirects already-signed-in users to /dashboard" do
      user = create(:user)
      sign_in_via_magic_link(user)

      get "/auth/sign_in"
      expect(response).to redirect_to("/dashboard")
    end

    it "passes through return_to into the form" do
      get "/auth/sign_in", params: { return_to: "/instances" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('value="/instances"')
    end
  end

  describe "DELETE /auth/sign_out" do
    let(:user) { create(:user) }

    it "revokes the active session, clears the cookie, and redirects to sign-in" do
      sign_in_via_magic_link(user)
      session = AuthSession.where(user: user).order(:created_at).last
      expect(session.revoked_at).to be_nil

      delete "/auth/sign_out"

      expect(response).to redirect_to("/auth/sign_in")
      expect(flash[:notice]).to eq("Signed out.")
      expect(session.reload.revoked_at).to be_present
    end

    it "is idempotent when no session is present" do
      delete "/auth/sign_out"
      expect(response).to redirect_to("/auth/sign_in")
    end

    it "records a signed_out audit event" do
      sign_in_via_magic_link(user)

      expect {
        delete "/auth/sign_out"
      }.to change { AuthEvent.where(kind: "signed_out", user: user).count }.by(1)
    end
  end
end
