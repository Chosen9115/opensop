# frozen_string_literal: true

module Auth
  # Invitation acceptance (GET /auth/invitations/:token).
  #
  # Phase 1 implementation: validates the token, consumes it, and signs the
  # user in. Phase 2 will replace this with the passkey-registration flow.
  class InvitationsController < BaseController
    # GET /auth/invitations/:token
    def show
      token = MagicLinkToken.from_token(params[:token])
      raise ActiveRecord::RecordNotFound unless token && token.purpose == "invitation"

      ActiveRecord::Base.transaction do
        token.consume!
        sign_in(token.user, via: "invitation")
      end

      Opensop::Auth::EventRecorder.call(
        kind: :invitation_consumed,
        user: token.user,
        request: request
      )

      redirect_to "/dashboard",
                  notice: I18n.t("opensop.auth.flash.invitation_accepted",
                                 default: "Welcome to OpenSOP. Register a passkey on this device to sign in next time.")
    end
  end
end
