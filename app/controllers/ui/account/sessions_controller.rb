# frozen_string_literal: true

module Ui
  module Account
    # Active session management. Lists every non-revoked, non-expired
    # AuthSession for the signed-in user, marks the current one (matched by
    # SHA-256 digest of the cookie token), and supports revoking individual
    # sessions or "all other sessions" in one shot. Revoking the current
    # session is blocked — the user is told to use Sign out instead.
    class SessionsController < BaseController
      helper_method :current_session_id

      def index
        @sessions = current_user
                    .auth_sessions
                    .active
                    .order(last_used_at: :desc, created_at: :desc)
      end

      def destroy
        session = current_user.auth_sessions.find(params[:id])

        if session.id == current_session_id
          redirect_to ui_account_sessions_path,
                      alert: t("opensop.auth.account.sessions.flash.cannot_revoke_current") and return
        end

        session.update!(revoked_at: Time.current)

        Opensop::Auth::EventRecorder.call(
          kind: :session_revoked,
          user: current_user,
          request: request,
          metadata: { auth_session_id: session.id }
        )

        redirect_to ui_account_sessions_path,
                    notice: t("opensop.auth.account.sessions.flash.revoked")
      end

      def destroy_others
        scope = current_user.auth_sessions.active
        scope = scope.where.not(id: current_session_id) if current_session_id
        count = scope.update_all(revoked_at: Time.current)

        Opensop::Auth::EventRecorder.call(
          kind: :sessions_others_revoked,
          user: current_user,
          request: request,
          metadata: { count: count }
        )

        redirect_to ui_account_sessions_path,
                    notice: t("opensop.auth.account.sessions.flash.others_revoked")
      end

      private

      # The id of the AuthSession backing the current request's cookie. nil
      # if no signed cookie is present (which shouldn't happen on a gated
      # page, but stay defensive). Memoized per-request.
      def current_session_id
        @current_session_id ||= begin
          raw = cookies.signed[Authenticatable::COOKIE_NAME]
          if raw.present?
            digest = Digest::SHA256.hexdigest(raw)
            current_user.auth_sessions.find_by(token_digest: digest)&.id
          end
        end
      end
    end
  end
end
