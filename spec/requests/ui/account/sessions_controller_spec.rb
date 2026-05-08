require "rails_helper"

RSpec.describe "Ui::Account::SessionsController", type: :request do
  let(:user) { create(:user) }

  before do
    sign_in_via_magic_link(user)
  end

  # Fetch the AuthSession backing the test cookie. sign_in_via_magic_link
  # creates exactly one session for the user, so the most recent active
  # session is the "current" one.
  let(:current_session) { user.auth_sessions.active.order(:created_at).last }

  describe "GET /account/sessions" do
    it "lists active sessions for the current user" do
      another = create(:auth_session, user: user, user_agent: "Other UA",
                                       ip_address: "10.0.0.1")
      stranger = create(:auth_session, user_agent: "Some stranger")

      get "/account/sessions"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Other UA")
      expect(response.body).not_to include("Some stranger")
      # Both the request session and the additional session belong to user
      expect([ current_session, another ].map(&:user_id).uniq).to eq([ user.id ])
    end
  end

  describe "DELETE /account/sessions/:id" do
    it "revokes a non-current session" do
      other = create(:auth_session, user: user, user_agent: "Other UA")

      expect {
        delete "/account/sessions/#{other.id}"
      }.to change { other.reload.revoked_at }.from(nil).to(be_present)

      expect(response).to redirect_to(ui_account_sessions_path)
      expect(flash[:notice]).to eq(I18n.t("opensop.auth.account.sessions.flash.revoked"))
    end

    it "blocks revoking the current session" do
      delete "/account/sessions/#{current_session.id}"

      expect(response).to redirect_to(ui_account_sessions_path)
      expect(flash[:alert]).to eq(I18n.t("opensop.auth.account.sessions.flash.cannot_revoke_current"))
      expect(current_session.reload.revoked_at).to be_nil
    end

    it "records a session_revoked audit event on success" do
      other = create(:auth_session, user: user, user_agent: "Other UA")

      expect {
        delete "/account/sessions/#{other.id}"
      }.to change { AuthEvent.where(kind: "session_revoked", user: user).count }.by(1)
    end
  end

  describe "DELETE /account/sessions/others" do
    it "revokes every active session except the current one" do
      keep = current_session
      drop1 = create(:auth_session, user: user, user_agent: "drop1")
      drop2 = create(:auth_session, user: user, user_agent: "drop2")

      delete "/account/sessions/others"

      expect(response).to redirect_to(ui_account_sessions_path)
      expect(flash[:notice]).to eq(I18n.t("opensop.auth.account.sessions.flash.others_revoked"))
      expect(keep.reload.revoked_at).to be_nil
      expect(drop1.reload.revoked_at).to be_present
      expect(drop2.reload.revoked_at).to be_present
    end

    it "records a sessions_others_revoked audit event with count metadata" do
      _drop1 = create(:auth_session, user: user, user_agent: "drop1")
      _drop2 = create(:auth_session, user: user, user_agent: "drop2")

      expect {
        delete "/account/sessions/others"
      }.to change { AuthEvent.where(kind: "sessions_others_revoked", user: user).count }.by(1)

      event = AuthEvent.where(kind: "sessions_others_revoked", user: user).order(:created_at).last
      expect(event.metadata["count"]).to eq(2)
    end
  end
end
