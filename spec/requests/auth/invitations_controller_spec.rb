require "rails_helper"

RSpec.describe "Auth::InvitationsController", type: :request do
  describe "GET /auth/invitations/:token" do
    let(:user) { create(:user) }

    it "consumes the invitation token, signs the user in, and redirects to /dashboard" do
      raw = Opensop::Auth::TokenIssuer.call(user: user, purpose: "invitation")

      expect {
        get "/auth/invitations/#{raw}"
      }.to change { AuthSession.where(user: user).count }.by(1)

      expect(response).to redirect_to("/dashboard")
      expect(flash[:notice]).to include("Welcome to OpenSOP")

      token = user.magic_link_tokens.last
      expect(token.consumed?).to be(true)
    end

    it "returns 404 when the token is a sign_in token (wrong route)" do
      raw = Opensop::Auth::TokenIssuer.call(user: user, purpose: "sign_in")
      get "/auth/invitations/#{raw}"
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 when the token does not exist" do
      get "/auth/invitations/nope"
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 when the token has been consumed" do
      raw = Opensop::Auth::TokenIssuer.call(user: user, purpose: "invitation")
      get "/auth/invitations/#{raw}"
      get "/auth/invitations/#{raw}"
      expect(response).to have_http_status(:not_found)
    end

    it "records an invitation_consumed audit event on success" do
      raw = Opensop::Auth::TokenIssuer.call(user: user, purpose: "invitation")
      expect {
        get "/auth/invitations/#{raw}"
      }.to change { AuthEvent.where(kind: "invitation_consumed", user: user).count }.by(1)
    end
  end
end
