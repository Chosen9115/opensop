# frozen_string_literal: true

# Mix-in providing cookie-backed session authentication for any controller
# that includes it. Reads the signed session cookie, looks up the matching
# AuthSession row by SHA-256 digest, slides expiry on touch, and exposes
# `current_user` / `signed_in?` to the controller and views.
#
# Phase 4 hard-cutover: session-based passkey auth is now the only gate on
# the admin UI. The cookie name is `:opensop_session`.
#
# Guarded bypass: when OPENSOP_DISABLE_AUTH is set to a truthy value AND the
# deployment is non-public (OPENSOP_RP_ID is unset or resolves to localhost /
# 127.0.0.1), `current_user` falls back to the bootstrap-admin User via
# `Opensop::AuthMode.bypass_user` when no valid session cookie is present.
# A real session cookie always takes precedence over the bypass. No AuthSession
# row is created and no cookie is set for bypass requests — auto-login is
# memoized only for the duration of the request.
# This bypass is OFF by default and silently ignored on public deployments.
module Authenticatable
  extend ActiveSupport::Concern

  COOKIE_NAME = :opensop_session
  SESSION_TTL = 30.days

  included do
    helper_method :current_user, :signed_in?
  end

  def current_user
    @current_user ||= begin
      raw = cookies.signed[COOKIE_NAME]
      session = AuthSession.from_token(raw)
      if session
        session.touch_usage!(expires_in: SESSION_TTL)
        session.user
      elsif Opensop::AuthMode.bypass?
        Opensop::AuthMode.bypass_user
      end
    end
  end

  def signed_in?
    current_user.present?
  end

  # Use this as a before_action on controllers that require a session.
  # Always enforces — unauthenticated callers get a 401 (JSON) or a
  # redirect to the sign-in page (HTML).
  def require_authentication
    return if signed_in?

    if request.format.json?
      render json: { error: "unauthorized" }, status: :unauthorized
    else
      redirect_to(auth_sign_in_path(return_to: request.fullpath),
                  alert: I18n.t("opensop.auth.errors.must_sign_in", default: "Please sign in."))
    end
  end

  # Used by Auth::* controllers after successful authentication.
  # `via:` records the path used to authenticate (e.g. "passkey",
  # "magic_link", "invitation", "recovery") into the audit log.
  def sign_in(user, via: nil)
    raw = SecureRandom.urlsafe_base64(32)
    AuthSession.create!(
      user: user,
      token_digest: Digest::SHA256.hexdigest(raw),
      user_agent: request.user_agent.to_s.first(255),
      ip_address: request.remote_ip,
      expires_at: SESSION_TTL.from_now
    )
    cookies.signed.permanent[COOKIE_NAME] = {
      value: raw,
      httponly: true,
      secure: Rails.env.production?,
      same_site: :lax
    }
    user.update_column(:last_signed_in_at, Time.current)
    @current_user = user
    Opensop::Auth::EventRecorder.call(
      kind: :signed_in,
      user: user,
      request: request,
      metadata: { via: via }
    )
    user
  end

  def sign_out
    raw = cookies.signed[COOKIE_NAME]
    session = AuthSession.from_token(raw)
    user = session&.user
    session&.update(revoked_at: Time.current)
    cookies.delete(COOKIE_NAME)
    @current_user = nil
    Opensop::Auth::EventRecorder.call(
      kind: :signed_out,
      user: user,
      request: request
    )
  end
end
