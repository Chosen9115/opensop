# frozen_string_literal: true

module Ui
  module Account
    # Self-service passkey management. Lists the signed-in user's passkeys,
    # supports renaming, and supports revocation with a guard that prevents
    # the user from removing their last passkey (which would lock them out).
    class PasskeysController < BaseController
      before_action :load_passkey, only: %i[update destroy]

      def index
        @passkeys = current_user.passkey_credentials.order(created_at: :desc)
      end

      def update
        new_nickname = passkey_params[:nickname].to_s.strip
        if @passkey.update(nickname: new_nickname)
          Opensop::Auth::EventRecorder.call(
            kind: :passkey_renamed,
            user: current_user,
            request: request,
            metadata: { passkey_credential_id: @passkey.id, nickname: @passkey.nickname }
          )
          respond_to do |format|
            format.turbo_stream do
              render turbo_stream: turbo_stream.replace(
                @passkey,
                partial: "ui/account/passkeys/row",
                locals: { passkey: @passkey }
              )
            end
            format.html do
              redirect_to ui_account_passkeys_path,
                          notice: t("opensop.auth.account.passkeys.flash.renamed")
            end
          end
        else
          respond_to do |format|
            format.turbo_stream do
              render turbo_stream: turbo_stream.replace(
                @passkey,
                partial: "ui/account/passkeys/row",
                locals: { passkey: @passkey }
              )
            end
            format.html do
              redirect_to ui_account_passkeys_path,
                          alert: @passkey.errors.full_messages.to_sentence
            end
          end
        end
      end

      def destroy
        if current_user.passkey_credentials.count <= 1
          redirect_to ui_account_passkeys_path,
                      alert: t("opensop.auth.account.passkeys.flash.last_passkey_blocked") and return
        end

        passkey_id = @passkey.id
        passkey_nickname = @passkey.nickname
        @passkey.destroy!

        Opensop::Auth::EventRecorder.call(
          kind: :passkey_revoked,
          user: current_user,
          request: request,
          metadata: { passkey_credential_id: passkey_id, nickname: passkey_nickname }
        )

        respond_to do |format|
          format.turbo_stream { render turbo_stream: turbo_stream.remove(@passkey) }
          format.html do
            redirect_to ui_account_passkeys_path,
                        notice: t("opensop.auth.account.passkeys.flash.revoked")
          end
        end
      end

      private

      def load_passkey
        @passkey = current_user.passkey_credentials.find(params[:id])
      end

      def passkey_params
        params.require(:passkey_credential).permit(:nickname)
      end
    end
  end
end
