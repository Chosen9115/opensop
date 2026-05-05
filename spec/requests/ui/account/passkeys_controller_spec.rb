require "rails_helper"

# /account/passkeys is gated by Ui::ApplicationController. Session auth is
# always on (Phase 4 cutover), so we just sign the user in.
RSpec.describe "Ui::Account::PasskeysController", type: :request do
  let(:user) { create(:user) }

  before do
    sign_in_via_magic_link(user)
  end

  describe "GET /account/passkeys" do
    it "lists only the current user's passkeys" do
      mine = create(:passkey_credential, user: user, nickname: "My MacBook")
      others = create(:passkey_credential, nickname: "Stranger device")

      get "/account/passkeys"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("My MacBook")
      expect(response.body).not_to include("Stranger device")
      expect(response.body).to include(mine.nickname)
    end
  end

  describe "PATCH /account/passkeys/:id" do
    it "renames a passkey and redirects with notice" do
      passkey = create(:passkey_credential, user: user, nickname: "Old name")

      patch "/account/passkeys/#{passkey.id}",
            params: { passkey_credential: { nickname: "New laptop" } }

      expect(response).to redirect_to(ui_account_passkeys_path)
      expect(flash[:notice]).to eq(I18n.t("opensop.auth.account.passkeys.flash.renamed"))
      expect(passkey.reload.nickname).to eq("New laptop")
    end

    it "rejects renaming a passkey that doesn't belong to the user" do
      other = create(:passkey_credential, nickname: "Not yours")

      patch "/account/passkeys/#{other.id}",
            params: { passkey_credential: { nickname: "Sneaky" } }

      expect(response).to have_http_status(:not_found)
      expect(other.reload.nickname).to eq("Not yours")
    end

    it "records a passkey_renamed audit event on success" do
      passkey = create(:passkey_credential, user: user, nickname: "Old name")

      expect {
        patch "/account/passkeys/#{passkey.id}",
              params: { passkey_credential: { nickname: "New laptop" } }
      }.to change { AuthEvent.where(kind: "passkey_renamed", user: user).count }.by(1)
    end
  end

  describe "DELETE /account/passkeys/:id" do
    it "revokes a passkey when the user has more than one" do
      keep = create(:passkey_credential, user: user, nickname: "Keep")
      drop = create(:passkey_credential, user: user, nickname: "Drop")

      delete "/account/passkeys/#{drop.id}"

      expect(response).to redirect_to(ui_account_passkeys_path)
      expect(flash[:notice]).to eq(I18n.t("opensop.auth.account.passkeys.flash.revoked"))
      expect { drop.reload }.to raise_error(ActiveRecord::RecordNotFound)
      expect(keep.reload).to be_present
    end

    it "blocks revocation of the last passkey" do
      passkey = create(:passkey_credential, user: user, nickname: "Only one")

      delete "/account/passkeys/#{passkey.id}"

      expect(response).to redirect_to(ui_account_passkeys_path)
      expect(flash[:alert]).to eq(I18n.t("opensop.auth.account.passkeys.flash.last_passkey_blocked"))
      expect(passkey.reload).to be_present
    end

    it "records a passkey_revoked audit event on success" do
      _keep = create(:passkey_credential, user: user, nickname: "Keep")
      drop = create(:passkey_credential, user: user, nickname: "Drop")

      expect {
        delete "/account/passkeys/#{drop.id}"
      }.to change { AuthEvent.where(kind: "passkey_revoked", user: user).count }.by(1)
    end
  end
end
