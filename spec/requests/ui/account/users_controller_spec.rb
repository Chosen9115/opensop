require "rails_helper"

RSpec.describe "Ui::Account::UsersController", type: :request do
  let(:user) { create(:user, email: "owner@example.com") }

  before do
    # Stub the mailer so specs never touch Resend.
    allow(Opensop::Auth::Mailer).to receive(:send_invitation)
    sign_in_via_magic_link(user)
  end

  describe "GET /account/users" do
    it "lists every admin in the system" do
      other = create(:user, email: "second@example.com")

      get "/account/users"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("owner@example.com")
      expect(response.body).to include(other.email)
    end
  end

  describe "POST /account/users" do
    it "creates the user, issues an invitation, and emails it" do
      expect {
        post "/account/users", params: {
          user: { email: "newadmin@example.com", display_name: "New Admin" }
        }
      }.to change(User, :count).by(1)
        .and change(MagicLinkToken, :count).by(1)

      created = User.find_by(email: "newadmin@example.com")
      expect(created.role).to eq("admin")
      expect(created.display_name).to eq("New Admin")

      token = created.magic_link_tokens.last
      expect(token.purpose).to eq("invitation")
      expect(token.expires_at).to be > 6.days.from_now

      expect(Opensop::Auth::Mailer).to have_received(:send_invitation).with(
        hash_including(user: created, inviter: user)
      )

      expect(response).to redirect_to(ui_account_users_path)
      expect(flash[:notice]).to include("newadmin@example.com")
    end

    it "records both user_invited and invitation_sent audit events on success" do
      expect {
        post "/account/users", params: {
          user: { email: "auditadmin@example.com", display_name: "Audit Admin" }
        }
      }.to change { AuthEvent.where(kind: "user_invited").count }.by(1)
        .and change { AuthEvent.where(kind: "invitation_sent").count }.by(1)
    end

    it "is a no-op when the email already exists" do
      create(:user, email: "taken@example.com")

      expect {
        post "/account/users", params: {
          user: { email: "taken@example.com", display_name: "dup" }
        }
      }.not_to change(User, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(flash.now[:alert]).to eq(I18n.t("opensop.auth.account.users.flash.email_taken"))
      expect(Opensop::Auth::Mailer).not_to have_received(:send_invitation)
    end
  end

  describe "DELETE /account/users/:id" do
    it "removes another admin" do
      other = create(:user, email: "doomed@example.com")

      expect { delete "/account/users/#{other.id}" }.to change(User, :count).by(-1)
      expect(response).to redirect_to(ui_account_users_path)
      expect(flash[:notice]).to include("doomed@example.com")
    end

    it "records a user_removed audit event on success" do
      other = create(:user, email: "audited@example.com")

      expect {
        delete "/account/users/#{other.id}"
      }.to change { AuthEvent.where(kind: "user_removed", user: user).count }.by(1)
    end

    it "blocks self-removal" do
      expect { delete "/account/users/#{user.id}" }.not_to change(User, :count)
      expect(response).to redirect_to(ui_account_users_path)
      expect(flash[:alert]).to eq(I18n.t("opensop.auth.account.users.flash.self_removal_blocked"))
    end

    it "blocks removing the last admin" do
      # Only the signed-in admin exists. We can't remove ourselves AND we
      # can't remove the only admin — verify last-admin check by creating
      # a second admin, signing them in, then deleting the OTHER user from
      # a fresh request after deleting the first admin (here we just verify
      # the pre-condition: a second admin who tries to delete a co-admin
      # when only two exist passes; deleting the remaining one fails).
      other = create(:user, email: "second@example.com")
      delete "/account/users/#{other.id}"
      expect(User.where(role: "admin").count).to eq(1)

      # With only one admin left, attempt self-removal is also blocked,
      # AND attempting to remove a (recreated) admin while signed in as
      # the sole admin requires picking a non-self target — the guard
      # first checks self-removal, so we directly test the count guard
      # by constructing a stub scenario.
      another = create(:user, email: "third@example.com")
      # Sanity: now 2 admins exist again.
      # Force the count check by stubbing the admin-count guard's count.
      allow(User).to receive_message_chain(:where, :count).and_return(1)
      delete "/account/users/#{another.id}"
      expect(response).to redirect_to(ui_account_users_path)
      expect(flash[:alert]).to eq(I18n.t("opensop.auth.account.users.flash.last_admin_blocked"))
    end
  end
end
